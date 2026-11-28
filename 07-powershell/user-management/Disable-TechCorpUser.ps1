<#
.SYNOPSIS
    Offboards a leaver the same day (BR-10): records, blocks, hands over and
    parks the account - in the order that keeps the mailbox (M365-CHG-002).

.DESCRIPTION
    Leaver procedure from user-accounts.md section 4 and
    licensing-and-lifecycle.md section 4 as one script:

      1. Safety checks - refuses privileged (adm-/wadm-, Admins OU, Domain
         Admins), break-glass and service accounts, and your own account.
      2. Record - appends the account's groups, manager, OU and description to
         a leaver record CSV BEFORE anything is removed (this is the rollback).
      3. Cloud (-IncludeCloud) - revoke Entra sessions, convert the mailbox to
         shared, give the manager Full Access and set an out-of-office reply.
         Needs Connect-MgGraph -Scopes User.RevokeSessions.All and
         Connect-ExchangeOnline beforehand; the script does not sign in.
      4. Disable the AD account and reset its password to a random value.
      5. Description "Left <date> <ticket>; groups: ..." (searchable in ADUC).
      6. Remove every group membership except the primary group (Domain Users)
         - this also removes LIC_M365_BusinessPremium, after the mailbox was
         converted to shared.
      7. Move to TechCorp/Disabled (synced, so the cloud account is blocked,
         not deleted). Delete after 30 days - Get-TechCorpStaleAccountReport.ps1
         lists those as DisabledPastRetention.

    Each step emits a row (Step, Status, Detail) and a log line. Every change
    supports -WhatIf / -Confirm. OneDrive access for the manager remains a
    manual step (tenant-specific URL) and is reported as MANUAL.

.PARAMETER Identity
    sAMAccountName of the leaver.

.PARAMETER Ticket
    Helpdesk ticket number of the HR request - required, it goes into the
    description and the record (no ticket, no offboarding).

.PARAMETER RecordPath
    Leaver record CSV (appended). Default .\output\leavers.csv.

.EXAMPLE
    .\Disable-TechCorpUser.ps1 -Identity connie.springer -Ticket HD-2027-0042 -WhatIf

.EXAMPLE
    Connect-MgGraph -Scopes User.RevokeSessions.All; Connect-ExchangeOnline
    .\Disable-TechCorpUser.ps1 -Identity connie.springer -Ticket HD-2027-0042 -IncludeCloud -AutoReplyContact jean.kirstein@techcorp.example

.NOTES
    Rollback (same day): Enable-ADAccount, Move-ADObject back to the OU in the
    record, Add-ADGroupMember for each group in the record, Set-Mailbox -Type Regular.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9.\-]{1,20}$')][string]$Identity,
    [Parameter(Mandatory)][ValidatePattern('^[A-Z]{2,5}-\d{4}-\d{3,6}$')][string]$Ticket,
    [datetime]$LeaveDate = (Get-Date),
    [switch]$IncludeCloud,
    [string]$AutoReplyContact,
    [string]$Server,
    [string]$DisabledOuDn = 'OU=Disabled,OU=TechCorp,DC=corp,DC=techcorp,DC=example',
    [string]$RecordPath = (Join-Path (Get-Location) 'output/leavers.csv'),
    [string]$LogPath = (Join-Path (Get-Location) 'output/logs/Disable-TechCorpUser.log')
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../modules/TechCorp.Admin/TechCorp.Admin.psd1') -Force
if (-not (Get-Command Get-ADUser -ErrorAction SilentlyContinue)) { Import-Module ActiveDirectory -ErrorAction Stop }
Write-TcLog -Message "$Identity | start | ticket $Ticket, cloud=$IncludeCloud, whatif=$WhatIfPreference" -Path $LogPath | Out-Null

$adParams = @{}
if ($Server) { $adParams.Server = $Server }
$steps = New-Object System.Collections.Generic.List[object]

function Add-Step([string]$Step, [string]$Status, [string]$Detail = '') {
    $row = [pscustomobject]@{ Identity = $Identity; Step = $Step; Status = $Status; Detail = $Detail }
    $steps.Add($row)
    $level = switch ($Status) { 'Done' { 'CHANGE' } 'Failed' { 'ERROR' } 'Refused' { 'ERROR' } default { 'INFO' } }
    Write-TcLog -Message "$Identity | $Step | $Status | $Detail" -Level $level -Path $LogPath | Out-Null
}

# 1. Safety checks ------------------------------------------------------------
$user = Get-ADUser -Identity $Identity -Properties MemberOf, Manager, Description, Enabled, UserPrincipalName, DisplayName, PrimaryGroup @adParams
$groups = @(Get-ADPrincipalGroupMembership -Identity $Identity @adParams | Where-Object { $_.DistinguishedName -ne $user.PrimaryGroup })
$groupNames = @($groups | ForEach-Object { $_.Name } | Sort-Object)

$refusal = $null
if ($Identity -match '^(w?adm|svc|bg)-') { $refusal = 'privileged, service or break-glass account - use the admin-account procedure' }
elseif ($user.DistinguishedName -match ',OU=Admin,OU=TechCorp,') { $refusal = 'account is in the Admin OU (tier 0/1)' }
elseif ($user.DistinguishedName -notmatch ',OU=(Users|Disabled),OU=TechCorp,') { $refusal = 'not a staff account (outside TechCorp/Users)' }
elseif ($groupNames -contains 'Domain Admins' -or $groupNames -contains 'Enterprise Admins') { $refusal = 'member of Domain/Enterprise Admins' }
elseif ($Identity -eq $env:USERNAME -or "adm-$Identity" -eq $env:USERNAME -or "wadm-$Identity" -eq $env:USERNAME) { $refusal = 'you cannot offboard yourself' }
if ($refusal) {
    Add-Step 'Safety check' 'Refused' $refusal
    $steps
    exit 2
}
Add-Step 'Safety check' 'PASS' "$($user.DisplayName), $($groupNames.Count) group(s), enabled=$($user.Enabled)"

$manager = $null
if ($user.Manager) { $manager = Get-ADUser -Identity $user.Manager -Properties UserPrincipalName @adParams }

# 2. Record (before any change - this is the rollback information) -------------
$record = [pscustomobject]@{
    Date              = $LeaveDate.ToString('yyyy-MM-dd')
    Ticket            = $Ticket
    SamAccountName    = $Identity
    DisplayName       = $user.DisplayName
    UserPrincipalName = $user.UserPrincipalName
    OriginalOu        = ($user.DistinguishedName -replace '^CN=.+?(?<!\\),', '')
    Manager           = $(if ($manager) { $manager.SamAccountName } else { '' })
    Groups            = ($groupNames -join ';')
    OldDescription    = [string]$user.Description
    RunBy             = $env:USERNAME
}
if ($WhatIfPreference) { Add-Step 'Record' 'WhatIf' "groups: $($record.Groups)" }
else {
    $dir = Split-Path -Parent $RecordPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $record | Export-Csv -LiteralPath $RecordPath -Append -NoTypeInformation -Encoding UTF8
    Add-Step 'Record' 'Done' $RecordPath
}

# 3. Cloud -------------------------------------------------------------------
if ($IncludeCloud) {
    $upn = $user.UserPrincipalName
    if ($PSCmdlet.ShouldProcess($upn, 'Revoke Entra ID sign-in sessions')) {
        try { Revoke-MgUserSignInSession -UserId $upn | Out-Null; Add-Step 'Revoke sessions' 'Done' }
        catch { Add-Step 'Revoke sessions' 'Failed' $_.Exception.Message }
    }
    else { Add-Step 'Revoke sessions' 'WhatIf' }

    if ($PSCmdlet.ShouldProcess($upn, 'Convert mailbox to shared')) {
        try { Set-Mailbox -Identity $upn -Type Shared; Add-Step 'Mailbox to shared' 'Done' }
        catch { Add-Step 'Mailbox to shared' 'Failed' $_.Exception.Message }
    }
    else { Add-Step 'Mailbox to shared' 'WhatIf' }

    if ($manager -and $PSCmdlet.ShouldProcess($upn, "Grant $($manager.UserPrincipalName) Full Access")) {
        try {
            Add-MailboxPermission -Identity $upn -User $manager.UserPrincipalName -AccessRights FullAccess -InheritanceType All | Out-Null
            Add-Step 'Manager mailbox access' 'Done' $manager.UserPrincipalName
        }
        catch { Add-Step 'Manager mailbox access' 'Failed' $_.Exception.Message }
    }
    elseif (-not $manager) { Add-Step 'Manager mailbox access' 'Skipped' 'no manager set in AD' }
    else { Add-Step 'Manager mailbox access' 'WhatIf' }

    $contact = if ($AutoReplyContact) { $AutoReplyContact } elseif ($manager) { $manager.UserPrincipalName } else { 'info@techcorp.example' }
    $message = "$($user.DisplayName) no longer works at TechCorp. Please contact $contact."
    if ($PSCmdlet.ShouldProcess($upn, 'Set out-of-office reply')) {
        try {
            Set-MailboxAutoReplyConfiguration -Identity $upn -AutoReplyState Enabled -InternalMessage $message -ExternalMessage $message
            Add-Step 'Out-of-office' 'Done' $contact
        }
        catch { Add-Step 'Out-of-office' 'Failed' $_.Exception.Message }
    }
    else { Add-Step 'Out-of-office' 'WhatIf' }

    Add-Step 'OneDrive access for manager' 'MANUAL' 'M365 admin center > user > OneDrive > Get access to files'
    if (@($steps | Where-Object { $_.Status -eq 'Failed' -and $_.Step -eq 'Mailbox to shared' }).Count -gt 0) {
        Add-Step 'Stop' 'Refused' 'mailbox not converted - groups (licence) kept so the mailbox is not lost; fix and re-run'
        $steps
        exit 2
    }
}
else {
    Add-Step 'Cloud steps' 'Skipped' 'run with -IncludeCloud, or do licensing-and-lifecycle.md section 4 by hand BEFORE the licence group is removed'
}

# 4. Disable and reset password ---------------------------------------------
if ($PSCmdlet.ShouldProcess($Identity, 'Disable account and reset password')) {
    Disable-ADAccount -Identity $Identity @adParams
    $random = Get-TcRandomPassword -Length 32
    Set-ADAccountPassword -Identity $Identity -Reset -NewPassword $random @adParams
    $random.Dispose()
    Add-Step 'Disable + reset password' 'Done'
}
else { Add-Step 'Disable + reset password' 'WhatIf' }

# 5. Description --------------------------------------------------------------
$description = "Left $($LeaveDate.ToString('yyyy-MM-dd')) $Ticket; groups: $($groupNames -join ', ')"
if ($description.Length -gt 1024) { $description = $description.Substring(0, 1021) + '...' }
if ($PSCmdlet.ShouldProcess($Identity, "Set description '$description'")) {
    Set-ADUser -Identity $Identity -Description $description @adParams
    Add-Step 'Description' 'Done' $description
}
else { Add-Step 'Description' 'WhatIf' $description }

# 6. Group memberships --------------------------------------------------------
foreach ($g in $groups) {
    if ($PSCmdlet.ShouldProcess($g.Name, "Remove $Identity")) {
        try { Remove-ADGroupMember -Identity $g -Members $Identity -Confirm:$false @adParams; Add-Step 'Remove group' 'Done' $g.Name }
        catch { Add-Step 'Remove group' 'Failed' "$($g.Name): $($_.Exception.Message)" }
    }
    else { Add-Step 'Remove group' 'WhatIf' $g.Name }
}

# 7. Move to Disabled OU ------------------------------------------------------
if ($user.DistinguishedName -like "*,$DisabledOuDn") { Add-Step 'Move to Disabled OU' 'Skipped' 'already there' }
elseif ($PSCmdlet.ShouldProcess($Identity, "Move to $DisabledOuDn")) {
    Move-ADObject -Identity $user.DistinguishedName -TargetPath $DisabledOuDn @adParams
    Add-Step 'Move to Disabled OU' 'Done' $DisabledOuDn
}
else { Add-Step 'Move to Disabled OU' 'WhatIf' $DisabledOuDn }

Add-Step 'Laptop' 'MANUAL' 'collect the laptop and rebuild it (laptop-build.md); set AssignedTo=Spare in hardware-inventory.csv; remove the employees.csv row'

$steps
if (@($steps | Where-Object Status -eq 'Failed').Count -gt 0) { exit 1 }
exit 0
