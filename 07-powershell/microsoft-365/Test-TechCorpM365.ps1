<#
.SYNOPSIS
    Verifies the Microsoft 365 tenant against the TechCorp plan and prints
    PASS / FAIL / SKIP per check. Read-only.

.DESCRIPTION
    Sync      - every staff account exists in Entra ID, is synced from AD,
                enabled, usageLocation GR; no on-prem admin account synced
    Licensing - Business Premium assigned through LIC_M365_BusinessPremium,
                every staff member licensed with no group-licensing errors
    Admins    - break-glass accounts exist and are Global Administrators;
                Global Administrators are only the break-glass accounts;
                the daily admin holds the planned roles
    Mail      - shared and room mailboxes, Full Access and Send As as planned,
                external tagging; DKIM (production)
    Teams     - dynamic rule, owners, team provisioned, channels
    SharePoint- tenant sharing ceiling, per-site sharing

    Connect first (Connect-MgGraph with Directory.Read.All, Group.Read.All,
    RoleManagement.Read.Directory; Connect-ExchangeOnline; Connect-MicrosoftTeams;
    Connect-SPOService). Missing connections are reported as SKIP.

.PARAMETER TenantDomain
    The tenant's onmicrosoft.com domain.

.PARAMETER LabTenant
    Expect onmicrosoft.com addresses (lab tenant).

.PARAMETER OutputPath
    Optional CSV path for the results.

.EXAMPLE
    .\Test-TechCorpM365.ps1 -LabTenant -TenantDomain contoso123.onmicrosoft.com -OutputPath .\output\m365.csv
#>
[CmdletBinding()]
param(
    [string]$TenantDomain = 'techcorpsolutions.onmicrosoft.com',

    [switch]$LabTenant,

    [string]$OutputPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$plan = & (Join-Path $PSScriptRoot 'Get-TechCorpM365Plan.ps1') -TenantDomain $TenantDomain -LabTenant:$LabTenant
$t = $plan.Tenant

$script:Results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$Area, [string]$Check, [string]$Status, [string]$Detail = '') {
    $script:Results.Add([pscustomobject]@{ Area = $Area; Check = $Check; Status = $Status; Detail = $Detail })
}
function Test-Check([string]$Area, [string]$Check, [bool]$Condition, [string]$Detail = '') {
    Add-Result $Area $Check $(if ($Condition) { 'PASS' } else { 'FAIL' }) $Detail
}
function Compare-Set([string[]]$Expected, [string[]]$Actual) {
    $missing = @($Expected | Where-Object { $_ -notin $Actual })
    $extra = @($Actual | Where-Object { $_ -notin $Expected })
    return ((@($(if ($missing) { "missing: $($missing -join ', ')" }), $(if ($extra) { "unexpected: $($extra -join ', ')" })) | Where-Object { $_ }) -join '; ')
}

$graph = $null
try { $graph = Get-MgContext } catch { $graph = $null }

# Sync, licensing, admins (Graph) ---------------------------------------------
if ($graph) {
    $sku = Get-MgSubscribedSku | Where-Object SkuPartNumber -eq $t.LicenceSkuPartNumber
    foreach ($u in $plan.Users) {
        $c = Get-MgUser -Filter "userPrincipalName eq '$($u.UserPrincipalName)'" -Property Id, AccountEnabled, OnPremisesSyncEnabled, UsageLocation, LicenseAssignmentStates
        if (-not $c) { Add-Result 'Sync' $u.UserPrincipalName 'FAIL' 'not in Entra ID'; continue }
        $problems = @()
        if (-not $c.OnPremisesSyncEnabled) { $problems += 'cloud-only (expected synced)' }
        if (-not $c.AccountEnabled) { $problems += 'disabled' }
        if ($c.UsageLocation -ne $t.UsageLocation) { $problems += "usageLocation '$($c.UsageLocation)'" }
        Test-Check 'Sync' $u.UserPrincipalName ($problems.Count -eq 0) ($problems -join '; ')
        if ($sku) {
            $state = @($c.LicenseAssignmentStates | Where-Object SkuId -eq $sku.SkuId)
            $ok = $state.Count -gt 0 -and @($state | Where-Object { $_.AssignedByGroup -and $_.State -eq 'Active' }).Count -gt 0
            Test-Check 'Licensing' $u.UserPrincipalName $ok $(if ($state) { "$($state[0].State) $($state[0].Error)" } else { 'no Business Premium' })
        }
    }
    if (-not $sku) { Add-Result 'Licensing' 'Business Premium subscription' 'FAIL' 'SKU SPB not in tenant' }
    foreach ($adm in 'adm-eren.yeager', 'wadm-eren.yeager') {
        $synced = Get-MgUser -Filter "startswith(userPrincipalName,'$adm@')" -Property Id, OnPremisesSyncEnabled | Where-Object OnPremisesSyncEnabled
        Test-Check 'Sync' "On-prem $adm not synced" (-not $synced)
    }

    $gaRole = Get-MgDirectoryRole -Filter "displayName eq 'Global Administrator'"
    $gaMembers = @()
    if ($gaRole) { $gaMembers = @(Get-MgDirectoryRoleMember -DirectoryRoleId $gaRole.Id -All | ForEach-Object { $_.AdditionalProperties['userPrincipalName'] }) }
    $expectedGa = @($plan.Admins | Where-Object { 'Global Administrator' -in $_.Roles } | ForEach-Object { $_.Account })
    $diff = Compare-Set $expectedGa $gaMembers
    Test-Check 'Admins' 'Global Administrators = break-glass accounts only' (-not $diff) $(if ($diff) { $diff } else { $gaMembers -join ', ' })
    foreach ($a in $plan.Admins | Where-Object Type -eq 'Admin') {
        $user = Get-MgUser -Filter "userPrincipalName eq '$($a.Account)'" -Property Id
        if (-not $user) { Add-Result 'Admins' $a.Account 'FAIL' 'missing'; continue }
        $assigned = @(Get-MgRoleManagementDirectoryRoleAssignment -Filter "principalId eq '$($user.Id)'" -All |
            ForEach-Object { (Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $_.RoleDefinitionId).DisplayName })
        $diff = Compare-Set $a.Roles $assigned
        Test-Check 'Admins' "$($a.Account) roles" (-not $diff) $diff
    }

    foreach ($team in $plan.Teams) {
        $g = Get-MgGroup -Filter "mailNickname eq '$($team.MailNickname)'" -Property Id, MembershipRule, MembershipRuleProcessingState, ResourceProvisioningOptions, Visibility
        if (-not $g) { Add-Result 'Teams' $team.Team 'FAIL' 'group missing'; continue }
        Test-Check 'Teams' "$($team.Team) dynamic rule" ($g.MembershipRule -eq $team.MembershipRule -and $g.MembershipRuleProcessingState -eq 'On') $g.MembershipRule
        Test-Check 'Teams' "$($team.Team) is a team, $($team.Visibility)" (('Team' -in @($g.ResourceProvisioningOptions)) -and $g.Visibility -eq $team.Visibility)
        $owners = @(Get-MgGroupOwner -GroupId $g.Id -All | ForEach-Object { ($_.AdditionalProperties['userPrincipalName'] -split '@')[0] })
        $diff = Compare-Set $team.Owners $owners
        Test-Check 'Teams' "$($team.Team) owners" (-not $diff) $diff
        if (Get-Command Get-TeamChannel -ErrorAction SilentlyContinue) {
            $channels = @(Get-TeamChannel -GroupId $g.Id -ErrorAction SilentlyContinue | ForEach-Object { $_.DisplayName })
            $missing = @($team.Channels | Where-Object { $_ -notin $channels })
            Test-Check 'Teams' "$($team.Team) channels" ($missing.Count -eq 0) $(if ($missing) { "missing: $($missing -join ', ')" } else { '' })
        }
    }
}
else { Add-Result 'Graph' 'Connect-MgGraph' 'SKIP' 'not connected - Sync, Licensing, Admins and Teams not checked' }

# Mail (Exchange Online) ------------------------------------------------------
if (Get-Command Get-EXOMailbox -ErrorAction SilentlyContinue) {
    foreach ($m in $plan.Mailboxes) {
        $mbx = Get-EXOMailbox -Identity $m.Address -ErrorAction SilentlyContinue
        if (-not $mbx) { Add-Result 'Mail' $m.Address 'FAIL' 'missing'; continue }
        $expectedType = if ($m.Type -eq 'Shared') { 'SharedMailbox' } else { 'RoomMailbox' }
        Test-Check 'Mail' "$($m.Address) type" ([string]$mbx.RecipientTypeDetails -eq $expectedType) ([string]$mbx.RecipientTypeDetails)
        $full = @(Get-EXOMailboxPermission -Identity $m.Address | Where-Object { $_.AccessRights -contains 'FullAccess' -and $_.User -like '*@*' } | ForEach-Object { ($_.User -split '@')[0] })
        $diff = Compare-Set $m.FullAccess $full
        Test-Check 'Mail' "$($m.Address) Full Access" (-not $diff) $diff
        $send = @(Get-EXORecipientPermission -Identity $m.Address | Where-Object { $_.Trustee -like '*@*' } | ForEach-Object { ($_.Trustee -split '@')[0] })
        $diff = Compare-Set $m.SendAs $send
        Test-Check 'Mail' "$($m.Address) Send As" (-not $diff) $diff
    }
    Test-Check 'Mail' 'External sender tag on' ([bool](Get-ExternalInOutlook).Enabled)
    if (-not $LabTenant) {
        $dkim = Get-DkimSigningConfig -Identity $t.MailDomain -ErrorAction SilentlyContinue
        Test-Check 'Mail' "DKIM enabled for $($t.MailDomain)" ($dkim -and $dkim.Enabled)
    }
    else { Add-Result 'Mail' 'DKIM' 'SKIP' 'lab tenant - onmicrosoft.com is signed by Microsoft' }
}
else { Add-Result 'Mail' 'Connect-ExchangeOnline' 'SKIP' 'not connected' }

# SharePoint ------------------------------------------------------------------
if (Get-Command Get-SPOTenant -ErrorAction SilentlyContinue) {
    $spo = $null
    try { $spo = Get-SPOTenant } catch { $spo = $null }
    if ($spo) {
        Test-Check 'SharePoint' "Tenant sharing = $($t.SharingCapability)" ([string]$spo.SharingCapability -eq $t.SharingCapability) ([string]$spo.SharingCapability)
        Test-Check 'SharePoint' 'Default link = specific people, view' ([string]$spo.DefaultSharingLinkType -eq $t.DefaultSharingLink -and [string]$spo.DefaultLinkPermission -eq $t.DefaultLinkPermission)
        foreach ($s in $plan.Sites) {
            $site = Get-SPOSite -Identity $s.Url -ErrorAction SilentlyContinue
            if (-not $site) { Add-Result 'SharePoint' $s.Url 'FAIL' 'missing'; continue }
            Test-Check 'SharePoint' "$($s.Site) sharing = $($s.ExternalSharing)" ([string]$site.SharingCapability -eq $s.ExternalSharing) ([string]$site.SharingCapability)
        }
    }
    else { Add-Result 'SharePoint' 'Connect-SPOService' 'SKIP' 'not connected' }
}
else { Add-Result 'SharePoint' 'SharePoint Online module' 'SKIP' 'module not installed' }

# Output ----------------------------------------------------------------------
$script:Results | Format-Table -AutoSize -Wrap
Write-Host (($script:Results | Group-Object Status | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ' | ')
if ($OutputPath) {
    $script:Results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "Results written to $OutputPath"
}
if (@($script:Results | Where-Object Status -eq 'FAIL').Count -gt 0) { exit 1 }
exit 0
