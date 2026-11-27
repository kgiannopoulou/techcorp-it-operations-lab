<#
.SYNOPSIS
    Builds TechCorp's Microsoft 365 plan (licensing, admin roles, shared and
    room mailboxes, Teams, SharePoint sites) from the repository CSVs - offline.

.DESCRIPTION
    Combines the Active Directory plan (Get-TechCorpAdPlan.ps1: users, OUs,
    licensing group) with:
      05-microsoft-365/tenant/cloud-admins.csv
      05-microsoft-365/exchange-online/mailboxes.csv
      05-microsoft-365/teams/teams.csv
      05-microsoft-365/sharepoint/sites.csv

    Team membership is not stored anywhere: every team is a Microsoft 365
    group with a DYNAMIC membership rule on the synced 'department' attribute
    (Entra ID P1 is included in Business Premium), so joiners, movers and
    leavers are handled by the HR data in AD.

    -SelfTest validates the plan (break-glass and role rules, mailbox owners,
    team owners and rules, sharing limits for sensitive sites, every employee's
    resulting teams) and runs in CI. -Summary prints who ends up in which team.

    -LabTenant switches every address to the tenant's onmicrosoft.com domain:
    the fictional techcorp.example can never be verified in a real tenant.

.PARAMETER TenantDomain
    Initial (onmicrosoft.com) domain of the tenant.

.PARAMETER LabTenant
    Use <alias>@<TenantDomain> instead of @techcorp.example everywhere.

.PARAMETER SelfTest
    Validate the plan. Exit code 0 = pass, 1 = fail.

.PARAMETER Summary
    Print team membership per employee.

.EXAMPLE
    ./Get-TechCorpM365Plan.ps1 -SelfTest

.EXAMPLE
    $plan = ./Get-TechCorpM365Plan.ps1 -LabTenant -TenantDomain contoso123.onmicrosoft.com
#>
[CmdletBinding(DefaultParameterSetName = 'Plan')]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,

    [string]$TenantDomain = 'techcorpsolutions.onmicrosoft.com',

    [switch]$LabTenant,

    [Parameter(ParameterSetName = 'SelfTest')]
    [switch]$SelfTest,

    [Parameter(ParameterSetName = 'Summary')]
    [switch]$Summary
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ad = & (Join-Path $Root '07-powershell/active-directory/Get-TechCorpAdPlan.ps1') -Root $Root
$mailDomain = if ($LabTenant) { $TenantDomain } else { $ad.UpnSuffix }
$tenantName = $TenantDomain.Split('.')[0]

$script:RepoRoot = $Root
function Import-PlanCsv([string]$RelativePath) {
    return @(Import-Csv -LiteralPath (Join-Path $script:RepoRoot $RelativePath) -Encoding UTF8)
}
$adminRows   = @(Import-PlanCsv '05-microsoft-365/tenant/cloud-admins.csv')
$mailboxRows = @(Import-PlanCsv '05-microsoft-365/exchange-online/mailboxes.csv')
$teamRows    = @(Import-PlanCsv '05-microsoft-365/teams/teams.csv')
$siteRows    = @(Import-PlanCsv '05-microsoft-365/sharepoint/sites.csv')
$departments = @(Import-PlanCsv '03-windows-server/users-and-groups/department-map.csv')

$deptByCode = @{}
foreach ($d in $departments) { $deptByCode[$d.Code] = $d }
$userByName = @{}
foreach ($u in $ad.Users) { $userByName[$u.SamAccountName] = $u }

function Get-CloudUpn([string]$Username) { return "$Username@$mailDomain" }

# --------------------------------------------------------------- plan objects
$users = @(foreach ($u in $ad.Users) {
    [pscustomobject]@{ Username = $u.SamAccountName; UserPrincipalName = Get-CloudUpn $u.SamAccountName; Department = $u.Department; UsageLocation = 'GR' }
})

$admins = @(foreach ($a in $adminRows) {
    [pscustomobject]@{ Account = $a.Account; Type = $a.Type; Roles = @($a.Roles -split ';' | Where-Object { $_ }); Licence = $a.Licence; Notes = $a.Notes }
})

$mailboxes = @(foreach ($m in $mailboxRows) {
    [pscustomobject]@{
        Alias        = $m.Alias
        Address      = "$($m.Alias)@$mailDomain"
        DisplayName  = $m.DisplayName
        Type         = $m.Type
        Capacity     = $(if ($m.Capacity) { [int]$m.Capacity } else { 0 })
        FullAccess   = @($m.FullAccess -split ';' | Where-Object { $_ })
        SendAs       = @($m.SendAs -split ';' | Where-Object { $_ })
        Purpose      = $m.Purpose
    }
})

$teams = @(foreach ($t in $teamRows) {
    $rule = if ($t.Department -eq 'All') {
        '(user.dirSyncEnabled -eq true) and (user.accountEnabled -eq true)'
    }
    elseif ($deptByCode.ContainsKey($t.Department)) {
        "(user.department -eq `"$($deptByCode[$t.Department].Department)`") and (user.accountEnabled -eq true)"
    }
    else { '' }
    [pscustomobject]@{
        Team           = $t.Team
        MailNickname   = $t.MailNickname
        Department     = $t.Department
        Visibility     = $t.Visibility
        GuestAccess    = ($t.GuestAccess -eq 'Yes')
        Owners         = @($t.Owners -split ';' | Where-Object { $_ })
        Channels       = @($t.Channels -split ';' | Where-Object { $_ })
        MembershipRule = $rule
    }
})

$sites = @(foreach ($s in $siteRows) {
    [pscustomobject]@{
        Site            = $s.Site
        Url             = "https://$tenantName.sharepoint.com$($s.Path)"
        Path            = $s.Path
        Kind            = $s.Kind
        Team            = $s.Team
        ExternalSharing = $s.ExternalSharing
        Owners          = @($s.Owners -split ';' | Where-Object { $_ })
        Notes           = $s.Notes
    }
})

# Tenant-wide settings (the ceiling for every site)
$tenant = [pscustomobject]@{
    TenantDomain          = $TenantDomain
    MailDomain            = $mailDomain
    AdminUrl              = "https://$tenantName-admin.sharepoint.com"
    LicenceGroup          = 'LIC_M365_BusinessPremium'
    LicenceSkuPartNumber  = 'SPB'      # Microsoft 365 Business Premium
    UsageLocation         = 'GR'
    SharingCapability     = 'ExternalUserSharingOnly'
    OneDriveSharing       = 'ExistingExternalUserSharingOnly'
    DefaultSharingLink    = 'Direct'   # "Specific people"
    DefaultLinkPermission = 'View'
    ExternalTagging       = $true
}

$plan = [pscustomobject]@{
    Tenant = $tenant; Users = $users; Admins = $admins; Mailboxes = $mailboxes; Teams = $teams; Sites = $sites
    LicenceGroupMembers = @(($ad.Groups | Where-Object Name -eq $tenant.LicenceGroup).Members)
    SyncedOus = @($ad.OUs | Where-Object EntraSync | ForEach-Object { $_.DistinguishedName })
}

if (-not $SelfTest -and -not $Summary) { return $plan }

function Get-UserTeam([string]$Username) {
    $u = $userByName[$Username]
    return @($teams | Where-Object {
        $_.Department -eq 'All' -or ($deptByCode.ContainsKey($_.Department) -and $deptByCode[$_.Department].Department -eq $u.Department)
    } | ForEach-Object { $_.MailNickname })
}

if ($Summary) {
    Write-Output '| User | Department | Teams |'
    Write-Output '|---|---|---|'
    foreach ($u in $users) { Write-Output "| $($u.Username) | $($u.Department) | $((Get-UserTeam $u.Username) -join ', ') |" }
    return
}

# --------------------------------------------------------------- self-test
$script:Failures = New-Object System.Collections.Generic.List[string]
$script:Passed = 0
function Assert-Plan([bool]$Condition, [string]$Message) {
    if ($Condition) { $script:Passed++ } else { $script:Failures.Add($Message) }
}
$knownRoles = 'Global Administrator', 'Global Reader', 'User Administrator', 'License Administrator', 'Groups Administrator',
    'Exchange Administrator', 'Teams Administrator', 'SharePoint Administrator', 'Hybrid Identity Administrator', 'Intune Administrator', 'Security Administrator'
$sharingRank = @{ Disabled = 0; ExistingExternalUserSharingOnly = 1; ExternalUserSharingOnly = 2; ExternalUserAndGuestSharing = 3 }

# Licensing and sync
Assert-Plan ($plan.LicenceGroupMembers.Count -eq $users.Count) "licensing: $($tenant.LicenceGroup) has $($plan.LicenceGroupMembers.Count) members, expected $($users.Count)"
Assert-Plan (@($ad.OUs | Where-Object { $_.Path -eq 'TechCorp/Groups/Licensing' -and $_.EntraSync }).Count -eq 1) 'sync: the licensing OU must be synced or the group never reaches Entra ID'

# Cloud admins
$bg = @($admins | Where-Object Type -eq 'BreakGlass')
Assert-Plan ($bg.Count -eq 2) "cloud-admins.csv: expected exactly 2 break-glass accounts, found $($bg.Count)"
$gaCount = @($admins | Where-Object { 'Global Administrator' -in $_.Roles }).Count
Assert-Plan ($gaCount -ge 2 -and $gaCount -le 4) "cloud-admins.csv: $gaCount Global Administrators - keep 2 to 4"
foreach ($a in $admins) {
    Assert-Plan ($a.Account -like "*@$TenantDomain") "cloud-admins.csv: '$($a.Account)' must be cloud-only on $TenantDomain (not synced, not on the mail domain)"
    Assert-Plan ($a.Type -in 'BreakGlass', 'Admin') "cloud-admins.csv: '$($a.Account)' type must be BreakGlass or Admin"
    Assert-Plan ($a.Licence -eq 'None') "cloud-admins.csv: '$($a.Account)' must not hold a licence (no mailbox, no apps)"
    foreach ($r in $a.Roles) { Assert-Plan ($r -in $knownRoles) "cloud-admins.csv: '$($a.Account)' unknown role '$r'" }
    if ($a.Type -eq 'Admin') { Assert-Plan ('Global Administrator' -notin $a.Roles) "cloud-admins.csv: daily admin '$($a.Account)' must not be Global Administrator - use specific roles" }
    if ($a.Type -eq 'BreakGlass') { Assert-Plan ($a.Account -match '^bg-admin\d{2}@') "cloud-admins.csv: break-glass '$($a.Account)' must be named bg-adminNN" }
}

# Mailboxes
$mailboxRows | Group-Object Alias | Where-Object Count -gt 1 | ForEach-Object { $script:Failures.Add("mailboxes.csv: duplicate alias '$($_.Name)'") }
foreach ($required in 'support', 'info', 'accounts') { Assert-Plan (@($mailboxes | Where-Object Alias -eq $required).Count -eq 1) "mailboxes.csv: BR-02 shared mailbox '$required@' missing" }
foreach ($m in $mailboxes) {
    Assert-Plan ($m.Alias -match '^[a-z][a-z0-9-]*$') "mailboxes.csv: alias '$($m.Alias)' must be lower-case letters, digits and hyphens"
    Assert-Plan (-not $userByName.ContainsKey($m.Alias)) "mailboxes.csv: '$($m.Alias)' collides with a user account"
    Assert-Plan ($m.Type -in 'Shared', 'Room') "mailboxes.csv: '$($m.Alias)' type must be Shared or Room"
    if ($m.Type -eq 'Shared') { Assert-Plan ($m.FullAccess.Count -gt 0) "mailboxes.csv: shared mailbox '$($m.Alias)' has nobody with Full Access" }
    if ($m.Type -eq 'Room') {
        Assert-Plan ($m.Capacity -gt 0) "mailboxes.csv: room '$($m.Alias)' needs a capacity"
        Assert-Plan ($m.Alias -like 'room-*') "mailboxes.csv: room '$($m.Alias)' must be named room-<name>"
    }
    foreach ($p in @($m.FullAccess) + @($m.SendAs)) { Assert-Plan ($userByName.ContainsKey($p)) "mailboxes.csv: '$($m.Alias)' grants access to unknown user '$p'" }
    foreach ($p in $m.SendAs) { Assert-Plan ($p -in $m.FullAccess) "mailboxes.csv: '$($m.Alias)' - $p has Send As without Full Access" }
}
$accounts = @($mailboxes | Where-Object Alias -eq 'accounts')
if ($accounts.Count -eq 1) {
    foreach ($p in $accounts[0].FullAccess) { Assert-Plan ($userByName[$p].Department -eq 'Finance') "mailboxes.csv: accounts@ (invoices, bank details) is Finance-only - $p is not in Finance" }
}

# Teams
$teamRows | Group-Object MailNickname | Where-Object Count -gt 1 | ForEach-Object { $script:Failures.Add("teams.csv: duplicate nickname '$($_.Name)'") }
$badChannelChars = '[~#%&*{}+/\\:<>?|''"]'
foreach ($t in $teams) {
    Assert-Plan ([bool]$t.MembershipRule) "teams.csv: '$($t.Team)' department '$($t.Department)' is not All or a department code"
    $expectedNick = if ($t.Department -eq 'All') { 'grp-all' } else { "grp-$($t.Department.ToLowerInvariant())" }
    Assert-Plan ($t.MailNickname -eq $expectedNick) "teams.csv: '$($t.Team)' nickname must be $expectedNick (naming convention grp-<department>)"
    Assert-Plan ($t.Visibility -in 'Private', 'Public') "teams.csv: '$($t.Team)' visibility must be Private or Public"
    if ($t.Department -ne 'All') { Assert-Plan ($t.Visibility -eq 'Private') "teams.csv: department team '$($t.Team)' must be Private" }
    Assert-Plan ($t.Owners.Count -ge 2) "teams.csv: '$($t.Team)' needs at least 2 owners (continuity when one is away)"
    foreach ($o in $t.Owners) {
        Assert-Plan ($userByName.ContainsKey($o)) "teams.csv: '$($t.Team)' owner '$o' is not an employee"
        if ($t.Department -ne 'All' -and $userByName.ContainsKey($o) -and $deptByCode.ContainsKey($t.Department)) {
            Assert-Plan ($userByName[$o].Department -eq $deptByCode[$t.Department].Department) "teams.csv: '$($t.Team)' owner '$o' is not in the department"
        }
    }
    foreach ($c in $t.Channels) {
        Assert-Plan ($c -notmatch $badChannelChars -and $c.Length -le 50) "teams.csv: '$($t.Team)' channel '$c' has characters Teams does not allow or is too long"
        Assert-Plan ($c -ne 'General') "teams.csv: '$($t.Team)' - General is created automatically"
    }
    if ($t.Department -in 'HR', 'Finance', 'Management') { Assert-Plan (-not $t.GuestAccess) "teams.csv: '$($t.Team)' holds sensitive data - guests not allowed (BR-26)" }
}
foreach ($u in $users) {
    $mine = Get-UserTeam $u.Username
    Assert-Plan ('grp-all' -in $mine) "teams: $($u.Username) is not in the company-wide team"
    $code = @($departments | Where-Object Department -eq $u.Department)[0].Code
    if (@($teams | Where-Object Department -eq $code).Count -gt 0) { Assert-Plan ($mine.Count -eq 2) "teams: $($u.Username) should be in grp-all and exactly one department team" }
}

# SharePoint
foreach ($s in $sites) {
    Assert-Plan ($s.Kind -in 'TeamSite', 'Communication') "sites.csv: '$($s.Site)' kind must be TeamSite or Communication"
    Assert-Plan ($s.ExternalSharing -in $sharingRank.Keys) "sites.csv: '$($s.Site)' unknown sharing level '$($s.ExternalSharing)'"
    if ($sharingRank.ContainsKey($s.ExternalSharing)) {
        Assert-Plan ($sharingRank[$s.ExternalSharing] -le $sharingRank[$tenant.SharingCapability]) "sites.csv: '$($s.Site)' sharing is wider than the tenant allows"
        Assert-Plan ($s.ExternalSharing -ne 'ExternalUserAndGuestSharing') "sites.csv: '$($s.Site)' - anonymous 'Anyone' links are not allowed"
    }
    foreach ($o in $s.Owners) { Assert-Plan ($userByName.ContainsKey($o)) "sites.csv: '$($s.Site)' owner '$o' is not an employee" }
    if ($s.Kind -eq 'TeamSite') {
        $t = @($teams | Where-Object MailNickname -eq $s.Team)
        Assert-Plan ($t.Count -eq 1) "sites.csv: '$($s.Site)' refers to unknown team '$($s.Team)'"
        Assert-Plan ($s.Path -eq "/sites/$($s.Team)") "sites.csv: '$($s.Site)' path must be /sites/$($s.Team) (created by the team)"
        if ($t.Count -eq 1) {
            if ($t[0].Department -in 'HR', 'Finance', 'Management') { Assert-Plan ($s.ExternalSharing -eq 'Disabled') "sites.csv: '$($s.Site)' holds sensitive data - external sharing must be Disabled (BR-26)" }
            if ($t[0].GuestAccess) { Assert-Plan ($s.ExternalSharing -eq 'ExternalUserSharingOnly') "sites.csv: '$($s.Site)' - team allows guests, so the site must allow new guests" }
        }
    }
}
foreach ($t in $teams) { Assert-Plan (@($sites | Where-Object Team -eq $t.MailNickname).Count -eq 1) "sites.csv: team '$($t.MailNickname)' has no site row" }

Write-Host ("M365 plan: {0} licensed users | {1} cloud admins | {2} mailboxes | {3} teams | {4} sites | {5} synced OUs" -f `
    $plan.LicenceGroupMembers.Count, $admins.Count, $mailboxes.Count, $teams.Count, $sites.Count, $plan.SyncedOus.Count)
if ($script:Failures.Count -gt 0) {
    $script:Failures | ForEach-Object { Write-Host "FAIL: $_" -ForegroundColor Red }
    Write-Host "$($script:Failures.Count) check(s) failed, $script:Passed passed." -ForegroundColor Red
    exit 1
}
Write-Host "All $script:Passed M365 plan checks passed." -ForegroundColor Green
exit 0
