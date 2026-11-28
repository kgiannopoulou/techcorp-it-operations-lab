<#
.SYNOPSIS
    Reminds account owners before a password expires (14, 7, 3 and 1 days)
    and lists expired ones. Report-only unless -SmtpServer is given.

.DESCRIPTION
    At TechCorp staff passwords never expire (NIST SP 800-63B, user-accounts.md
    section 3); the privileged adm-/wadm- accounts expire after 365 days
    (PSO-AdminAccounts). An expired admin password is found at the worst
    moment - during an incident - so the owner is reminded in advance.

    Expiry comes from msDS-UserPasswordExpiryTimeComputed, which AD
    calculates with the fine-grained policy applied, so no policy values are
    hard-coded. Admin accounts have no mailbox: the reminder goes to the
    owner's normal account (adm-eren.yeager -> eren.yeager's e-mail).

    One reminder per threshold (not one per day), so the script can run
    daily as a scheduled task. With -SmtpServer it sends through the SMTP
    relay (production: the Exchange Online connector on port 25,
    M365-CHG-001; lab: any test SMTP server) - every send supports -WhatIf.

    -InputCsv reads an export instead of AD (SamAccountName, Enabled,
    PasswordLastSet, PasswordNeverExpires, ExpiresOn, EmailAddress).

.EXAMPLE
    .\Send-TechCorpPasswordExpiryNotice.ps1
    Report only - who would be reminded today.

.EXAMPLE
    .\Send-TechCorpPasswordExpiryNotice.ps1 -SmtpServer techcorp-example.mail.protection.outlook.com -From it-noreply@techcorp.example -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InputCsv,
    [int[]]$NotifyDays = @(14, 7, 3, 1),
    [string]$SmtpServer,
    [int]$Port = 25,
    [switch]$UseSsl,
    [string]$From = 'it-noreply@techcorp.example',
    [string]$Helpdesk = 'helpdesk@techcorp.example',
    [string]$SearchBase = 'OU=TechCorp,DC=corp,DC=techcorp,DC=example',
    [string]$Server,
    [string]$OutputFolder = (Join-Path (Get-Location) 'output/reports'),
    [datetime]$Now = (Get-Date)
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../modules/TechCorp.Admin/TechCorp.Admin.psd1') -Force

if ($InputCsv) {
    $accounts = @(Import-Csv -LiteralPath $InputCsv -Encoding UTF8)
}
else {
    if (-not (Get-Command Get-ADUser -ErrorAction SilentlyContinue)) { Import-Module ActiveDirectory -ErrorAction Stop }
    $adParams = @{ SearchBase = $SearchBase }
    if ($Server) { $adParams.Server = $Server }
    $props = 'DisplayName', 'EmailAddress', 'Enabled', 'PasswordLastSet', 'PasswordNeverExpires', 'msDS-UserPasswordExpiryTimeComputed'
    $accounts = @(Get-ADUser -Filter 'Enabled -eq $true' -Properties $props @adParams | ForEach-Object {
        $ft = [int64]$_.'msDS-UserPasswordExpiryTimeComputed'
        # 0 = must change at next logon, max value = never expires
        $expires = if ($ft -gt 0 -and $ft -lt [int64]::MaxValue) { [datetime]::FromFileTime($ft) } else { $null }
        [pscustomobject]@{
            SamAccountName = $_.SamAccountName; DisplayName = $_.DisplayName; EmailAddress = $_.EmailAddress
            Enabled = $_.Enabled; PasswordLastSet = $_.PasswordLastSet; PasswordNeverExpires = $_.PasswordNeverExpires
            ExpiresOn = $expires
        }
    })
}

# owner e-mail for admin accounts without a mailbox
$mailByName = @{}
foreach ($a in $accounts) { if ($a.PSObject.Properties['EmailAddress'] -and $a.EmailAddress) { $mailByName[$a.SamAccountName] = $a.EmailAddress } }

$expiry = @(Get-TcPasswordExpiry -Account $accounts -NotifyDays $NotifyDays -Now $Now)
$due = @($expiry | Where-Object Notify | ForEach-Object {
    $to = $_.EmailAddress
    if (-not $to -and $_.SamAccountName -match '^w?adm-(.+)$' -and $mailByName.ContainsKey($Matches[1])) { $to = $mailByName[$Matches[1]] }
    $_ | Add-Member -NotePropertyName Recipient -NotePropertyValue ([string]$to) -PassThru |
        Add-Member -NotePropertyName Sent -NotePropertyValue 'No' -PassThru
})

if ($SmtpServer) {
    foreach ($d in $due) {
        if (-not $d.Recipient) { $d.Sent = 'No recipient'; continue }
        $msg = Get-TcPasswordExpiryMessage -Expiry $d -Helpdesk $Helpdesk
        if ($PSCmdlet.ShouldProcess($d.Recipient, "Send '$($msg.Subject)'")) {
            $mail = New-Object System.Net.Mail.MailMessage($From, $d.Recipient, $msg.Subject, $msg.Body)
            $client = New-Object System.Net.Mail.SmtpClient($SmtpServer, $Port)
            $client.EnableSsl = [bool]$UseSsl
            try { $client.Send($mail); $d.Sent = 'Yes' }
            catch { $d.Sent = "Failed: $($_.Exception.Message)" }
            finally { $mail.Dispose(); $client.Dispose() }
        }
        else { $d.Sent = 'WhatIf' }
    }
}

if (-not (Test-Path -LiteralPath $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force -WhatIf:$false | Out-Null }
$csv = Join-Path $OutputFolder "password-expiry-$($Now.ToString('yyyy-MM-dd')).csv"
$expiry | Where-Object { $_.State -in 'ExpiringSoon', 'Expired' } | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8 -WhatIf:$false

$soon = @($expiry | Where-Object State -eq 'ExpiringSoon').Count
$expired = @($expiry | Where-Object State -eq 'Expired').Count
Write-Host "Password expiry: $($expiry.Count) account(s) checked, $soon expiring within $(($NotifyDays | Measure-Object -Maximum).Maximum) days, $expired expired, $($due.Count) reminder(s) due today -> $csv"
$due
if ($expired -gt 0 -or @($due | Where-Object { $_.Sent -like 'Failed*' }).Count -gt 0) { exit 1 }
exit 0
