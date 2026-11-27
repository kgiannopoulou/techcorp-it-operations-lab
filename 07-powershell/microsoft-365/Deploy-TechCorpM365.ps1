<#
.SYNOPSIS
    Applies the TechCorp Microsoft 365 plan to the tenant: usage location,
    group-based licensing, shared and room mailboxes, dynamic Microsoft 365
    groups turned into Teams with channels, SharePoint sharing limits.

.DESCRIPTION
    Idempotent - every object is looked up first. Supports -WhatIf.
    Run as the cloud admin account (adm-eren.yeager@<tenant>) AFTER Entra
    Connect has synced the users and LIC_M365_BusinessPremium.

    Steps (each can be skipped with -Skip):
      Users      - usageLocation = GR on every synced staff account (licences fail without it)
      Licensing  - Business Premium (SPB) assigned to the synced licensing group
      Mail       - shared + room mailboxes, Full Access (auto-mapped) and Send As,
                   room auto-accept, external sender tag, DKIM (production only)
      Teams      - dynamic M365 groups (department rule), owners, guest setting,
                   team creation, channels
      SharePoint - tenant sharing ceiling, default link type, OneDrive sync limited
                   to domain-joined PCs, per-site sharing, intranet communication site

    Required modules: Microsoft.Graph (Users, Groups, Identity.DirectoryManagement),
    ExchangeOnlineManagement, MicrosoftTeams, Microsoft.Online.SharePoint.PowerShell
    (Windows PowerShell 5.1). Connect first, or use -Connect.

.PARAMETER TenantDomain
    The tenant's onmicrosoft.com domain.

.PARAMETER LabTenant
    Use the onmicrosoft.com domain for every address (techcorp.example cannot be verified).

.PARAMETER AdDomainGuid
    ObjectGUID of corp.techcorp.example ((Get-ADDomain).ObjectGUID) - restricts
    OneDrive sync to domain-joined PCs. Skipped when not given.

.PARAMETER Connect
    Run Connect-MgGraph, Connect-ExchangeOnline, Connect-MicrosoftTeams and Connect-SPOService.

.PARAMETER Skip
    Steps to skip: Users, Licensing, Mail, Teams, SharePoint.

.EXAMPLE
    .\Deploy-TechCorpM365.ps1 -LabTenant -TenantDomain contoso123.onmicrosoft.com -Connect -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$TenantDomain = 'techcorpsolutions.onmicrosoft.com',

    [switch]$LabTenant,

    [guid]$AdDomainGuid,

    [switch]$Connect,

    [ValidateSet('Users', 'Licensing', 'Mail', 'Teams', 'SharePoint')]
    [string[]]$Skip = @()
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$plan = & (Join-Path $PSScriptRoot 'Get-TechCorpM365Plan.ps1') -TenantDomain $TenantDomain -LabTenant:$LabTenant
$t = $plan.Tenant

function Write-Step([string]$Step, [string]$Object, [string]$Result) {
    Write-Host ('{0,-11} {1,-42} {2}' -f $Step, $Object, $Result)
}

if ($Connect) {
    Connect-MgGraph -Scopes 'User.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All', 'Organization.Read.All' -NoWelcome
    Connect-ExchangeOnline -ShowBanner:$false
    $null = Connect-MicrosoftTeams
    Connect-SPOService -Url $t.AdminUrl
}

$userIdCache = @{}
function Get-CloudUserId([string]$Username) {
    if ($userIdCache.ContainsKey($Username)) { return $userIdCache[$Username] }
    $upn = ($plan.Users | Where-Object Username -eq $Username).UserPrincipalName
    $u = Get-MgUser -Filter "userPrincipalName eq '$upn'" -Property Id, UsageLocation
    if (-not $u) { throw "User $upn not found in Entra ID - has Entra Connect synced it?" }
    $userIdCache[$Username] = $u.Id
    return $u.Id
}

# Users ----------------------------------------------------------------------
if ('Users' -notin $Skip) {
    foreach ($u in $plan.Users) {
        $cloud = Get-MgUser -Filter "userPrincipalName eq '$($u.UserPrincipalName)'" -Property Id, UsageLocation
        if (-not $cloud) { Write-Step 'User' $u.UserPrincipalName 'WARN not synced yet'; continue }
        if ($cloud.UsageLocation -ne $u.UsageLocation -and $PSCmdlet.ShouldProcess($u.UserPrincipalName, "usageLocation = $($u.UsageLocation)")) {
            Update-MgUser -UserId $cloud.Id -UsageLocation $u.UsageLocation
            Write-Step 'User' $u.UserPrincipalName "updated (usageLocation $($u.UsageLocation))"
        }
    }
}

# Licensing ------------------------------------------------------------------
if ('Licensing' -notin $Skip) {
    $sku = Get-MgSubscribedSku | Where-Object SkuPartNumber -eq $t.LicenceSkuPartNumber
    $group = Get-MgGroup -Filter "displayName eq '$($t.LicenceGroup)'" -Property Id, AssignedLicenses, OnPremisesSyncEnabled
    if (-not $sku) { Write-Step 'Licence' $t.LicenceSkuPartNumber 'WARN no Business Premium subscription in this tenant' }
    elseif (-not $group) { Write-Step 'Licence' $t.LicenceGroup 'WARN group not synced - check the Licensing OU is in the sync scope' }
    elseif ($sku.SkuId -notin @($group.AssignedLicenses | ForEach-Object { $_.SkuId }) -and $PSCmdlet.ShouldProcess($t.LicenceGroup, 'Assign Business Premium')) {
        $null = Set-MgGroupLicense -GroupId $group.Id -AddLicenses @(@{ SkuId = $sku.SkuId }) -RemoveLicenses @()
        Write-Step 'Licence' $t.LicenceGroup "updated (SPB, $($sku.PrepaidUnits.Enabled) seats)"
    }
    else { Write-Step 'Licence' $t.LicenceGroup 'exists' }
}

# Mail -----------------------------------------------------------------------
if ('Mail' -notin $Skip) {
    foreach ($m in $plan.Mailboxes) {
        $mbx = Get-EXOMailbox -Identity $m.Address -ErrorAction SilentlyContinue
        if (-not $mbx -and $PSCmdlet.ShouldProcess($m.Address, "Create $($m.Type) mailbox")) {
            if ($m.Type -eq 'Shared') {
                $null = New-Mailbox -Shared -Name $m.DisplayName -Alias $m.Alias -DisplayName $m.DisplayName -PrimarySmtpAddress $m.Address
            }
            else {
                $null = New-Mailbox -Room -Name $m.DisplayName -Alias $m.Alias -DisplayName $m.DisplayName -PrimarySmtpAddress $m.Address -ResourceCapacity $m.Capacity
                Set-CalendarProcessing -Identity $m.Address -AutomateProcessing AutoAccept -AllowConflicts $false -BookingWindowInDays 180 -AddOrganizerToSubject $true
            }
            Write-Step 'Mailbox' $m.Address 'created'
        }
        elseif ($mbx) { Write-Step 'Mailbox' $m.Address 'exists' }

        $fullNow = @(Get-EXOMailboxPermission -Identity $m.Address -ErrorAction SilentlyContinue | Where-Object { $_.AccessRights -contains 'FullAccess' } | ForEach-Object { $_.User })
        foreach ($p in $m.FullAccess) {
            $upn = ($plan.Users | Where-Object Username -eq $p).UserPrincipalName
            if ($upn -notin $fullNow -and $PSCmdlet.ShouldProcess($m.Address, "Full Access for $upn")) {
                $null = Add-MailboxPermission -Identity $m.Address -User $upn -AccessRights FullAccess -InheritanceType All -AutoMapping $true
                Write-Step 'FullAccess' $m.Address "added $upn"
            }
        }
        $sendNow = @(Get-EXORecipientPermission -Identity $m.Address -ErrorAction SilentlyContinue | ForEach-Object { $_.Trustee })
        foreach ($p in $m.SendAs) {
            $upn = ($plan.Users | Where-Object Username -eq $p).UserPrincipalName
            if ($upn -notin $sendNow -and $PSCmdlet.ShouldProcess($m.Address, "Send As for $upn")) {
                $null = Add-RecipientPermission -Identity $m.Address -Trustee $upn -AccessRights SendAs -Confirm:$false
                Write-Step 'SendAs' $m.Address "added $upn"
            }
        }
    }
    if ($PSCmdlet.ShouldProcess('Exchange Online', 'Tag external senders in Outlook')) {
        Set-ExternalInOutlook -Enabled $true
        Write-Step 'Org' 'External sender tag' 'updated (on)'
    }
    if (-not $LabTenant) {
        $dkim = Get-DkimSigningConfig -Identity $t.MailDomain -ErrorAction SilentlyContinue
        if ($dkim -and -not $dkim.Enabled -and $PSCmdlet.ShouldProcess($t.MailDomain, 'Enable DKIM signing')) {
            Set-DkimSigningConfig -Identity $t.MailDomain -Enabled $true
            Write-Step 'DKIM' $t.MailDomain 'updated (enabled)'
        }
    }
}

# Teams ----------------------------------------------------------------------
if ('Teams' -notin $Skip) {
    $guestTemplate = Get-MgDirectorySettingTemplate | Where-Object DisplayName -eq 'Group.Unified.Guest'
    foreach ($team in $plan.Teams) {
        $g = Get-MgGroup -Filter "mailNickname eq '$($team.MailNickname)'" -Property Id, MembershipRule, ResourceProvisioningOptions
        if (-not $g) {
            if (-not $PSCmdlet.ShouldProcess($team.MailNickname, "Create dynamic M365 group: $($team.MembershipRule)")) { continue }
            $g = New-MgGroup -DisplayName $team.Team -MailNickname $team.MailNickname -MailEnabled:$true -SecurityEnabled:$false `
                -GroupTypes @('Unified', 'DynamicMembership') -MembershipRule $team.MembershipRule -MembershipRuleProcessingState 'On' `
                -Visibility $team.Visibility -Description "TechCorp $($team.Team) - managed from teams.csv"
            Write-Step 'Group' $team.MailNickname 'created (dynamic)'
        }
        elseif ($g.MembershipRule -ne $team.MembershipRule -and $PSCmdlet.ShouldProcess($team.MailNickname, 'Update membership rule')) {
            Update-MgGroup -GroupId $g.Id -MembershipRule $team.MembershipRule
            Write-Step 'Group' $team.MailNickname 'updated (rule)'
        }

        $owners = @(Get-MgGroupOwner -GroupId $g.Id -All | ForEach-Object { $_.Id })
        foreach ($o in $team.Owners) {
            $id = Get-CloudUserId $o
            if ($id -notin $owners -and $PSCmdlet.ShouldProcess($team.MailNickname, "Owner $o")) {
                New-MgGroupOwnerByRef -GroupId $g.Id -BodyParameter @{ '@odata.id' = "https://graph.microsoft.com/v1.0/users/$id" }
                Write-Step 'Owner' $team.MailNickname "added $o"
            }
        }

        if (-not $team.GuestAccess -and $guestTemplate) {
            $existing = @(Get-MgGroupSetting -GroupId $g.Id -ErrorAction SilentlyContinue | Where-Object TemplateId -eq $guestTemplate.Id)
            if ($existing.Count -eq 0 -and $PSCmdlet.ShouldProcess($team.MailNickname, 'Block adding guests')) {
                $null = New-MgGroupSetting -GroupId $g.Id -BodyParameter @{ templateId = $guestTemplate.Id; values = @(@{ name = 'AllowToAddGuests'; value = 'false' }) }
                Write-Step 'Guests' $team.MailNickname 'blocked'
            }
        }

        if ('Team' -notin @($g.ResourceProvisioningOptions) -and $PSCmdlet.ShouldProcess($team.MailNickname, 'Create team from group')) {
            $null = New-Team -GroupId $g.Id
            Write-Step 'Team' $team.Team 'created'
        }
        $channels = @(Get-TeamChannel -GroupId $g.Id -ErrorAction SilentlyContinue | ForEach-Object { $_.DisplayName })
        foreach ($c in $team.Channels) {
            if ($c -notin $channels -and $PSCmdlet.ShouldProcess("$($team.Team) / $c", 'Create channel')) {
                $null = New-TeamChannel -GroupId $g.Id -DisplayName $c
                Write-Step 'Channel' "$($team.Team) / $c" 'created'
            }
        }
    }
}

# SharePoint -----------------------------------------------------------------
if ('SharePoint' -notin $Skip) {
    if ($PSCmdlet.ShouldProcess('SharePoint tenant', "Sharing ceiling $($t.SharingCapability), links $($t.DefaultSharingLink)/$($t.DefaultLinkPermission)")) {
        Set-SPOTenant -SharingCapability $t.SharingCapability -OneDriveSharingCapability $t.OneDriveSharing `
            -DefaultSharingLinkType $t.DefaultSharingLink -DefaultLinkPermission $t.DefaultLinkPermission
        Write-Step 'Tenant' 'SharePoint / OneDrive sharing' 'updated'
    }
    if ($AdDomainGuid -and $PSCmdlet.ShouldProcess('OneDrive', "Sync only on PCs joined to $AdDomainGuid")) {
        Set-SPOTenantSyncClientRestriction -Enable -DomainGuids $AdDomainGuid.ToString()
        Write-Step 'Tenant' 'OneDrive sync restriction' 'updated (domain-joined only)'
    }
    foreach ($s in $plan.Sites) {
        $site = Get-SPOSite -Identity $s.Url -ErrorAction SilentlyContinue
        if (-not $site) {
            if ($s.Kind -eq 'Communication' -and $PSCmdlet.ShouldProcess($s.Url, 'Create communication site')) {
                $ownerUpn = ($plan.Users | Where-Object Username -eq $s.Owners[0]).UserPrincipalName
                New-SPOSite -Url $s.Url -Title $s.Site -Owner $ownerUpn -Template 'SITEPAGEPUBLISHING#0' -StorageQuota 26214400
                Write-Step 'Site' $s.Url 'created'
            }
            else { Write-Step 'Site' $s.Url 'WARN not provisioned yet (team site appears after the team is created)'; continue }
        }
        $current = Get-SPOSite -Identity $s.Url -ErrorAction SilentlyContinue
        if ($current -and [string]$current.SharingCapability -ne $s.ExternalSharing -and $PSCmdlet.ShouldProcess($s.Url, "Sharing $($s.ExternalSharing)")) {
            Set-SPOSite -Identity $s.Url -SharingCapability $s.ExternalSharing
            Write-Step 'Site' $s.Url "updated (sharing $($s.ExternalSharing))"
        }
    }
}
Write-Host 'Done. Verify with Test-TechCorpM365.ps1.'
