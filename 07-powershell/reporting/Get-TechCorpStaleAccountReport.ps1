<#
.SYNOPSIS
    Monthly stale-account review: inactive, never-used and over-retained
    user and computer accounts, as CSV + HTML. Read-only.

.DESCRIPTION
    Finds accounts an attacker would love and nobody would miss:

      Inactive              enabled, no logon for -InactiveDays (default 45)
      NeverLoggedOn         enabled, created more than -InactiveDays ago, never used
      PasswordNeverExpires  flag set on a staff account (the domain policy already
                            has no expiry - the flag would bypass a future policy)
      DisabledPastRetention disabled longer than -DisabledRetentionDays (30): the
                            leaver procedure deletes these

    Live mode reads TechCorp/Users, TechCorp/Disabled and TechCorp/Computers
    (Get-ADUser / Get-ADComputer). -InputCsv instead reads an export with
    the columns SamAccountName/Name, Enabled, LastLogonDate, WhenCreated,
    WhenChanged, PasswordNeverExpires, DistinguishedName, ObjectClass -
    useful for reviewing an export offline, and how the tests run.

    The script never disables or deletes anything: the review is a decision
    for a person (BR-26 access review). Exit code 0 = nothing found, 1 = findings.

.PARAMETER InactiveDays
    Minimum 14: lastLogonTimestamp only replicates every 9-14 days.

.PARAMETER AllowNeverExpires
    Accounts allowed to have PasswordNeverExpires (none for staff at TechCorp).

.EXAMPLE
    .\Get-TechCorpStaleAccountReport.ps1 -OutputFolder \\TC-FS01\IT$\Reports\stale

.EXAMPLE
    ./Get-TechCorpStaleAccountReport.ps1 -InputCsv ./ad-export.csv -Now 2027-06-01
#>
[CmdletBinding()]
param(
    [ValidateRange(14, 3650)][int]$InactiveDays = 45,
    [int]$DisabledRetentionDays = 30,
    [string[]]$AllowNeverExpires = @(),
    [string]$InputCsv,
    [switch]$UsersOnly,
    [string]$SearchBase = 'OU=TechCorp,DC=corp,DC=techcorp,DC=example',
    [string]$Server,
    [string]$OutputFolder = (Join-Path (Get-Location) 'output/reports'),
    [datetime]$Now = (Get-Date)
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../modules/TechCorp.Admin/TechCorp.Admin.psd1') -Force

if ($InputCsv) {
    $rows = @(Import-Csv -LiteralPath $InputCsv -Encoding UTF8)
    $users = @($rows | Where-Object { -not $_.PSObject.Properties['ObjectClass'] -or $_.ObjectClass -ne 'computer' })
    $computers = @($rows | Where-Object { $_.PSObject.Properties['ObjectClass'] -and $_.ObjectClass -eq 'computer' })
    $source = "export $InputCsv"
}
else {
    if (-not (Get-Command Get-ADUser -ErrorAction SilentlyContinue)) { Import-Module ActiveDirectory -ErrorAction Stop }
    $adParams = @{ SearchBase = $SearchBase; Filter = '*' }
    if ($Server) { $adParams.Server = $Server }
    # Admin accounts (TechCorp/Admin) are reviewed too - they matter most
    $users = @(Get-ADUser @adParams -Properties LastLogonDate, WhenCreated, WhenChanged, PasswordNeverExpires, Enabled)
    $computers = @()
    if (-not $UsersOnly) { $computers = @(Get-ADComputer @adParams -Properties LastLogonDate, WhenCreated, WhenChanged, Enabled) }
    $source = "Active Directory $SearchBase"
}

$staleUsers = @(Get-TcStaleAccount -Account $users -InactiveDays $InactiveDays -DisabledRetentionDays $DisabledRetentionDays -AllowNeverExpires $AllowNeverExpires -Now $Now)
$staleComputers = @()
if (-not $UsersOnly -and $computers.Count -gt 0) {
    # computers change their password every 30 days, so 45+ days without logon = gone
    $staleComputers = @(Get-TcStaleAccount -Account $computers -InactiveDays $InactiveDays -DisabledRetentionDays $DisabledRetentionDays -Now $Now)
}

$all = @($staleUsers | Select-Object @{ n = 'Type'; e = { 'User' } }, *) + @($staleComputers | Select-Object @{ n = 'Type'; e = { 'Computer' } }, *)

if (-not (Test-Path -LiteralPath $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null }
$stamp = $Now.ToString('yyyy-MM-dd')
$csv = Join-Path $OutputFolder "stale-accounts-$stamp.csv"
$html = Join-Path $OutputFolder "stale-accounts-$stamp.html"
$all | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
$summary = @(
    [pscustomobject]@{ Item = 'Source'; Value = $source }
    [pscustomobject]@{ Item = 'Users checked'; Value = $users.Count }
    [pscustomobject]@{ Item = 'Computers checked'; Value = $computers.Count }
    [pscustomobject]@{ Item = 'Inactive threshold (days)'; Value = $InactiveDays }
    [pscustomobject]@{ Item = 'Accounts with findings'; Value = $all.Count }
)
ConvertTo-TcHtmlReport -Title "Stale account review $stamp" -Now $Now -Section ([ordered]@{
    'Summary'   = $summary
    'Users'     = $staleUsers
    'Computers' = $staleComputers
}) | Set-Content -LiteralPath $html -Encoding UTF8

Write-Host ("Stale accounts: {0} user(s), {1} computer(s) of {2}/{3} checked -> {4}" -f $staleUsers.Count, $staleComputers.Count, $users.Count, $computers.Count, $html)
$all
if ($all.Count -gt 0) { exit 1 }
exit 0
