<#
.SYNOPSIS
    Builds TechCorp's Active Directory, Group Policy and file-permission plan
    from the repository CSV files - offline, no domain needed.

.DESCRIPTION
    Reads the single sources of truth:
      00-company-overview/data/employees.csv
      01-office-deployment/equipment-inventory/hardware-inventory.csv
      03-windows-server/users-and-groups/{ou-structure,department-map,ad-groups,admin-accounts}.csv
      03-windows-server/file-services/folders.csv
      03-windows-server/permissions/{file-permissions,access-tests}.csv
      03-windows-server/group-policy/{gpo-plan,gpo-registry-settings}.csv

    and turns them into one plan object (OUs with distinguished names, users,
    admin accounts, groups with resolved members, pre-staged computers,
    folders, NTFS permissions, GPOs and their registry settings).

    The deployment scripts (Deploy-TechCorpAd.ps1, Deploy-TechCorpFileShare.ps1,
    Deploy-TechCorpGpo.ps1) and the verification script (Test-TechCorpAd.ps1)
    all consume this plan, so the CSVs are the only place a change is made.

    -SelfTest validates the plan (naming conventions, AGDLP rules, nesting
    loops, references between files) and computes every user's effective
    access to every folder, comparing it with access-tests.csv. It runs in CI.

    -Summary prints the effective-access matrix as a Markdown table.

    Read-only: never connects to Active Directory and changes nothing.

.PARAMETER Root
    Repository root. Defaults to two levels above this script.

.PARAMETER DomainDn
    Distinguished name of the AD domain (default DC=corp,DC=techcorp,DC=example).

.PARAMETER UpnSuffix
    UPN / e-mail suffix for staff accounts (default techcorp.example).

.PARAMETER SelfTest
    Validate the plan and the expected access tests. Exit code 0 = pass, 1 = fail.

.PARAMETER Summary
    Print object counts and the effective-access matrix (Markdown).

.EXAMPLE
    ./Get-TechCorpAdPlan.ps1 -SelfTest

.EXAMPLE
    $plan = ./Get-TechCorpAdPlan.ps1
    $plan.Users | Format-Table SamAccountName, OuPath, Title

.EXAMPLE
    ./Get-TechCorpAdPlan.ps1 -Summary
#>
[CmdletBinding(DefaultParameterSetName = 'Plan')]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,

    [string]$DomainDn = 'DC=corp,DC=techcorp,DC=example',

    [string]$UpnSuffix = 'techcorp.example',

    [Parameter(ParameterSetName = 'SelfTest')]
    [switch]$SelfTest,

    [Parameter(ParameterSetName = 'Summary')]
    [switch]$Summary
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$AccessRank = @{ None = 0; List = 1; RO = 2; RW = 3 }
$BuiltInGroups = @('Domain Admins', 'Protected Users')
$DeviceTierOu = @{
    Standard  = 'TechCorp/Computers/Workstations/Standard'
    Creative  = 'TechCorp/Computers/Workstations/Standard'
    Developer = 'TechCorp/Computers/Workstations/Developer'
    IT        = 'TechCorp/Computers/Workstations/IT'
}
$ServerOu = 'TechCorp/Computers/Servers'
$DomainFqdn = (($DomainDn -split ',') | ForEach-Object { $_ -replace '^DC=', '' }) -join '.'

# ---------------------------------------------------------------- load data
function Import-PlanCsv([string]$RelativePath) {
    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing data file: $RelativePath" }
    return @(Import-Csv -LiteralPath $path -Encoding UTF8)
}

$employees     = @(Import-PlanCsv '00-company-overview/data/employees.csv')
$inventory     = @(Import-PlanCsv '01-office-deployment/equipment-inventory/hardware-inventory.csv')
$ouRows        = @(Import-PlanCsv '03-windows-server/users-and-groups/ou-structure.csv')
$departments   = @(Import-PlanCsv '03-windows-server/users-and-groups/department-map.csv')
$groupRows     = @(Import-PlanCsv '03-windows-server/users-and-groups/ad-groups.csv')
$adminRows     = @(Import-PlanCsv '03-windows-server/users-and-groups/admin-accounts.csv')
$folderRows    = @(Import-PlanCsv '03-windows-server/file-services/folders.csv')
$permRows      = @(Import-PlanCsv '03-windows-server/permissions/file-permissions.csv')
$accessTests   = @(Import-PlanCsv '03-windows-server/permissions/access-tests.csv')
$gpoRows       = @(Import-PlanCsv '03-windows-server/group-policy/gpo-plan.csv')
$gpoSettingRows = @(Import-PlanCsv '03-windows-server/group-policy/gpo-registry-settings.csv')

# ---------------------------------------------------------------- helpers
function ConvertTo-OuDn([string]$Path) {
    $parts = $Path.Split('/')
    [Array]::Reverse($parts)
    return ((@($parts | ForEach-Object { "OU=$_" }) -join ',') + ",$DomainDn")
}

function Get-ParentPath([string]$Path, [string]$Separator) {
    $i = $Path.LastIndexOf($Separator)
    if ($i -lt 0) { return '' }
    return $Path.Substring(0, $i)
}

# ---------------------------------------------------------------- build plan
$deptByName = @{}
foreach ($d in $departments) { $deptByName[$d.Department] = $d }

$employeeByName = @{}
foreach ($e in $employees) { $employeeByName[$e.Username] = $e }

$ous = @(foreach ($o in $ouRows) {
    $parent = Get-ParentPath $o.Path '/'
    [pscustomobject]@{
        Path              = $o.Path
        Name              = $o.Path.Split('/')[-1]
        ParentPath        = $parent
        DistinguishedName = ConvertTo-OuDn $o.Path
        ParentDn          = $(if ($parent) { ConvertTo-OuDn $parent } else { $DomainDn })
        Description       = $o.Description
    }
})

$users = @(foreach ($e in $employees) {
    $ouPath = ''
    if ($deptByName.ContainsKey($e.Department)) { $ouPath = $deptByName[$e.Department].UserOU }
    [pscustomobject]@{
        SamAccountName    = $e.Username
        GivenName         = $e.FirstName
        Surname           = $e.LastName
        DisplayName       = "$($e.FirstName) $($e.LastName)"
        UserPrincipalName = "$($e.Username)@$UpnSuffix"
        EmailAddress      = "$($e.Username)@$UpnSuffix"
        EmployeeID        = $e.EmployeeID
        Department        = $e.Department
        Title             = $e.JobTitle
        Manager           = $e.Manager
        Company           = 'TechCorp Solutions'
        Office            = 'Athens HQ'
        OuPath            = $ouPath
        OuDn              = $(if ($ouPath) { ConvertTo-OuDn $ouPath } else { '' })
    }
})

$adminAccounts = @(foreach ($a in $adminRows) {
    $displayName = $a.Username
    if ($employeeByName.ContainsKey($a.Owner)) {
        $o = $employeeByName[$a.Owner]
        $displayName = "$($o.FirstName) $($o.LastName) ($(($a.Username -split '-')[0]))"
    }
    [pscustomobject]@{
        SamAccountName    = $a.Username
        Owner             = $a.Owner
        DisplayName       = $displayName
        # Admin accounts use the AD domain as UPN suffix: they are never synced to Microsoft 365 and have no mailbox.
        UserPrincipalName = "$($a.Username)@$DomainFqdn"
        OuPath            = $a.OU
        OuDn              = ConvertTo-OuDn $a.OU
        BuiltInGroups     = @($a.MemberOf -split ';' | Where-Object { $_ })
        Description       = $a.Purpose
    }
})

$groups = @(foreach ($g in $groupRows) {
    $members = @()
    if ($g.Members -eq '@department') {
        $dept = @($departments | Where-Object { $_.RoleGroup -eq $g.Name })
        if ($dept.Count -eq 1) {
            $members = @($employees | Where-Object { $_.Department -eq $dept[0].Department } | ForEach-Object { $_.Username })
        }
    }
    elseif ($g.Members) {
        $members = @($g.Members -split ';' | Where-Object { $_ })
    }
    [pscustomobject]@{
        Name             = $g.Name
        Scope            = $g.Scope
        OuPath           = $g.OU
        OuDn             = ConvertTo-OuDn $g.OU
        Members          = $members
        MembersFromDept  = ($g.Members -eq '@department')
        Description      = $g.Description
    }
})

$computers = @(foreach ($a in $inventory) {
    $ouPath = $null
    if ($a.Category -eq 'Laptop') {
        $tier = 'Standard'
        if ($a.AssignedTo -and $employeeByName.ContainsKey($a.AssignedTo)) { $tier = $employeeByName[$a.AssignedTo].DeviceTier }
        $ouPath = $DeviceTierOu[$tier]
    }
    elseif ($a.Category -eq 'Virtual server' -and $a.Hostname -notlike 'TC-DC*') {
        $ouPath = $ServerOu
    }
    if (-not $ouPath) { continue }
    [pscustomobject]@{
        Name        = $a.Hostname
        OuPath      = $ouPath
        OuDn        = ConvertTo-OuDn $ouPath
        Description = "$($a.Model) - $(if ($a.AssignedTo) { $a.AssignedTo } else { 'spare' })"
    }
})

$folders = @(foreach ($f in $folderRows) {
    [pscustomobject]@{
        Folder           = $f.Folder
        Parent           = Get-ParentPath $f.Folder '\'
        Share            = $f.Share
        BreakInheritance = ($f.BreakInheritance -eq 'Yes')
        Description      = $f.Description
    }
})

$permissions = @(foreach ($p in $permRows) {
    [pscustomobject]@{ Folder = $p.Folder; Group = $p.Group; Access = $p.Access }
})

$gpos = @(foreach ($g in $gpoRows) {
    [pscustomobject]@{
        Name              = $g.Name
        Type              = $g.Type
        LinkTarget        = $g.LinkTarget
        SecurityFiltering = @($g.SecurityFiltering -split ';' | Where-Object { $_ })
        Method            = $g.Method
        Settings          = $g.Settings
        Requirements      = $g.Requirements
    }
})

$gpoSettings = @(foreach ($s in $gpoSettingRows) {
    [pscustomobject]@{ Gpo = $s.GPO; Key = $s.Key; ValueName = $s.ValueName; Type = $s.Type; Value = $s.Value; Setting = $s.Setting }
})

$plan = [pscustomobject]@{
    DomainDn      = $DomainDn
    DomainFqdn    = $DomainFqdn
    UpnSuffix     = $UpnSuffix
    OUs           = $ous
    Users         = $users
    AdminAccounts = $adminAccounts
    Groups        = $groups
    Computers     = $computers
    Folders       = $folders
    Permissions   = $permissions
    Gpos          = $gpos
    GpoSettings   = $gpoSettings
    AccessTests   = $accessTests
}

if (-not $SelfTest -and -not $Summary) { return $plan }

# ---------------------------------------------------------------- effective access model
$directMemberOf = @{}
foreach ($g in $groups) {
    foreach ($m in $g.Members) {
        if (-not $directMemberOf.ContainsKey($m)) { $directMemberOf[$m] = New-Object System.Collections.Generic.List[string] }
        $directMemberOf[$m].Add($g.Name)
    }
}

function Get-TransitiveGroup([string]$Principal) {
    $seen = @{}
    $queue = New-Object System.Collections.Generic.Queue[string]
    $queue.Enqueue($Principal)
    while ($queue.Count -gt 0) {
        $p = $queue.Dequeue()
        if (-not $directMemberOf.ContainsKey($p)) { continue }
        foreach ($g in $directMemberOf[$p]) {
            if (-not $seen.ContainsKey($g)) { $seen[$g] = $true; $queue.Enqueue($g) }
        }
    }
    return $seen
}

$folderByPath = @{}
foreach ($f in $folders) { $folderByPath[$f.Folder] = $f }
$permsByFolder = @{}
foreach ($p in $permissions) {
    if (-not $permsByFolder.ContainsKey($p.Folder)) { $permsByFolder[$p.Folder] = New-Object System.Collections.Generic.List[object] }
    $permsByFolder[$p.Folder].Add($p)
}

# Models how the deployment script writes the ACLs: RW/RO ACEs inherit to
# everything below, List applies to "this folder only", a folder with
# BreakInheritance keeps only its own ACEs (plus Administrators/SYSTEM).
# No Deny ACEs are used anywhere, so the highest grant wins.
function Get-EffectiveAccess([string]$User, [string]$Folder) {
    $tokens = Get-TransitiveGroup $User
    $best = 'None'
    $current = $Folder
    $isTarget = $true
    while ($current) {
        if (-not $folderByPath.ContainsKey($current)) { break }
        if ($permsByFolder.ContainsKey($current)) {
            foreach ($p in $permsByFolder[$current]) {
                if (-not $isTarget -and $p.Access -eq 'List') { continue }
                if ($tokens.ContainsKey($p.Group) -and $AccessRank[$p.Access] -gt $AccessRank[$best]) { $best = $p.Access }
            }
        }
        if ($folderByPath[$current].BreakInheritance) { break }
        $current = $folderByPath[$current].Parent
        $isTarget = $false
    }
    return $best
}

# ---------------------------------------------------------------- summary
if ($Summary) {
    Write-Host ("OUs: {0} | Users: {1} | Admin accounts: {2} | Groups: {3} | Computers: {4} | Folders: {5} | ACEs: {6} | GPOs: {7} | GPO registry values: {8}" -f `
        $ous.Count, $users.Count, $adminAccounts.Count, $groups.Count, $computers.Count, $folders.Count, $permissions.Count, $gpos.Count, $gpoSettings.Count)
    $columns = @($folders | ForEach-Object { $_.Folder })
    $short = @($columns | ForEach-Object { ($_ -replace '^Departments\\', '') })
    Write-Output ('| User | ' + ($short -join ' | ') + ' |')
    Write-Output ('|---|' + (($columns | ForEach-Object { ':-:' }) -join '|') + '|')
    $symbol = @{ None = '-'; List = 'L'; RO = 'R'; RW = '**W**' }
    foreach ($u in $users) {
        $cells = foreach ($c in $columns) { $symbol[(Get-EffectiveAccess $u.SamAccountName $c)] }
        Write-Output ("| $($u.SamAccountName) | " + ($cells -join ' | ') + ' |')
    }
    return
}

# ---------------------------------------------------------------- self-test
$script:Failures = New-Object System.Collections.Generic.List[string]
$script:Passed = 0
function Assert-Plan([bool]$Condition, [string]$Message) {
    if ($Condition) { $script:Passed++ } else { $script:Failures.Add($Message) }
}

$ouPaths = @{}
foreach ($o in $ous) { $ouPaths[$o.Path] = $true }
$principals = @{}
foreach ($u in $users) { $principals[$u.SamAccountName] = 'User' }
foreach ($a in $adminAccounts) { $principals[$a.SamAccountName] = 'Admin' }
$groupByName = @{}
foreach ($g in $groups) { $groupByName[$g.Name] = $g; $principals[$g.Name] = 'Group' }

# OUs
foreach ($o in $ous) {
    Assert-Plan ((-not $o.ParentPath) -or $ouPaths.ContainsKey($o.ParentPath)) "ou-structure.csv: parent of '$($o.Path)' is not defined"
    Assert-Plan ($o.Name -match '^[A-Za-z][A-Za-z0-9 -]*$') "ou-structure.csv: OU name '$($o.Name)' has characters that need escaping in a DN"
}
Assert-Plan (@($ous | Where-Object { -not $_.ParentPath }).Count -eq 1) 'ou-structure.csv: there must be exactly one top-level OU'

# Departments and users
foreach ($e in $employees) { Assert-Plan ($deptByName.ContainsKey($e.Department)) "department-map.csv: employee department '$($e.Department)' is not mapped" }
foreach ($d in $departments) {
    Assert-Plan ($ouPaths.ContainsKey($d.UserOU)) "department-map.csv: OU '$($d.UserOU)' is not in ou-structure.csv"
    Assert-Plan ($groupByName.ContainsKey($d.RoleGroup)) "department-map.csv: group '$($d.RoleGroup)' is not in ad-groups.csv"
    Assert-Plan ($d.RoleGroup -eq "GG_$($d.Code)_Users") "department-map.csv: role group for $($d.Code) should be GG_$($d.Code)_Users"
    Assert-Plan ($folderByPath.ContainsKey($d.DepartmentFolder)) "department-map.csv: folder '$($d.DepartmentFolder)' is not in folders.csv"
}
foreach ($u in @($users) + @($adminAccounts)) {
    Assert-Plan ($u.SamAccountName.Length -le 20) "account '$($u.SamAccountName)' exceeds 20 characters (sAMAccountName limit)"
}
foreach ($a in $adminAccounts) {
    Assert-Plan ($a.SamAccountName -match '^(adm|wadm)-[a-z]+\.[a-z]+$') "admin-accounts.csv: '$($a.SamAccountName)' must be adm-<user> or wadm-<user>"
    Assert-Plan ($employeeByName.ContainsKey($a.Owner)) "admin-accounts.csv: owner '$($a.Owner)' is not an employee"
    Assert-Plan ($a.SamAccountName -like "*-$($a.Owner)") "admin-accounts.csv: '$($a.SamAccountName)' does not match its owner '$($a.Owner)'"
    Assert-Plan ($a.OuPath -like 'TechCorp/Admin/*' -and $ouPaths.ContainsKey($a.OuPath)) "admin-accounts.csv: '$($a.SamAccountName)' must live under TechCorp/Admin"
    foreach ($b in $a.BuiltInGroups) { Assert-Plan ($b -in $BuiltInGroups) "admin-accounts.csv: unknown built-in group '$b'" }
    if ($a.SamAccountName -like 'wadm-*') { Assert-Plan ('Domain Admins' -notin $a.BuiltInGroups) "admin-accounts.csv: workstation admin '$($a.SamAccountName)' must not be a Domain Admin" }
}
$daCount = @($adminAccounts | Where-Object { 'Domain Admins' -in $_.BuiltInGroups }).Count
Assert-Plan ($daCount -ge 1 -and $daCount -le 2) "admin-accounts.csv: expected 1-2 Domain Admin accounts, found $daCount"

# Groups: naming, scope, AGDLP
# GG_<Department>_<Role>  |  DL_<ResourceType>_<Resource>[-<Subfolder>]_<RW|RO|List>
$groupNamePattern = '^(GG_[A-Za-z]+_[A-Za-z]+|DL_[A-Z]+_[A-Za-z]+(-[A-Za-z]+)?_(RW|RO|List))$'
$groupRows | Group-Object Name | Where-Object Count -gt 1 | ForEach-Object { $script:Failures.Add("ad-groups.csv: duplicate group '$($_.Name)'") }
foreach ($g in $groups) {
    Assert-Plan ($g.Name -match $groupNamePattern) "ad-groups.csv: '$($g.Name)' does not follow GG_/DL_ naming"
    Assert-Plan ($g.Name.Length -le 64) "ad-groups.csv: '$($g.Name)' is too long"
    Assert-Plan ($ouPaths.ContainsKey($g.OuPath)) "ad-groups.csv: '$($g.Name)' OU '$($g.OuPath)' is not defined"
    if ($g.Name -like 'GG_*') {
        Assert-Plan ($g.Scope -eq 'Global') "ad-groups.csv: '$($g.Name)' is GG_ but scope is $($g.Scope)"
        Assert-Plan ($g.OuPath -in 'TechCorp/Groups/Role', 'TechCorp/Admin/Groups') "ad-groups.csv: global group '$($g.Name)' must be in Groups/Role or Admin/Groups"
    }
    if ($g.Name -like 'DL_*') {
        Assert-Plan ($g.Scope -eq 'DomainLocal') "ad-groups.csv: '$($g.Name)' is DL_ but scope is $($g.Scope)"
        Assert-Plan ($g.OuPath -eq 'TechCorp/Groups/Resource') "ad-groups.csv: domain local group '$($g.Name)' must be in Groups/Resource"
    }
    if ($g.MembersFromDept) {
        Assert-Plan (@($departments | Where-Object { $_.RoleGroup -eq $g.Name }).Count -eq 1) "ad-groups.csv: '$($g.Name)' uses @department but is not a RoleGroup in department-map.csv"
    }
    Assert-Plan ($g.Members.Count -gt 0) "ad-groups.csv: '$($g.Name)' has no members"
    foreach ($m in $g.Members) {
        if (-not $principals.ContainsKey($m)) { $script:Failures.Add("ad-groups.csv: '$($g.Name)' member '$m' does not exist"); continue }
        $kind = $principals[$m]
        if ($g.Scope -eq 'DomainLocal') {
            # AGDLP: only global groups go into domain local groups - never accounts
            Assert-Plan ($kind -eq 'Group' -and $m -like 'GG_*') "AGDLP: domain local group '$($g.Name)' contains '$m' - only GG_ groups allowed"
        }
        else {
            Assert-Plan ($kind -ne 'Group' -or $m -like 'GG_*') "AGDLP: global group '$($g.Name)' contains non-global group '$m'"
        }
        if ($g.OuPath -eq 'TechCorp/Admin/Groups') { Assert-Plan ($kind -eq 'Admin') "ad-groups.csv: admin group '$($g.Name)' contains non-admin account '$m'" }
        if ($kind -eq 'Admin') { Assert-Plan ($g.OuPath -eq 'TechCorp/Admin/Groups') "ad-groups.csv: privileged account '$m' is in non-admin group '$($g.Name)'" }
    }
    Assert-Plan (-not (Get-TransitiveGroup $g.Name).ContainsKey($g.Name)) "ad-groups.csv: '$($g.Name)' is nested inside itself (loop)"
}
foreach ($d in $departments) {
    Assert-Plan ((Get-TransitiveGroup $d.RoleGroup).ContainsKey('GG_All_Staff')) "ad-groups.csv: $($d.RoleGroup) is not nested in GG_All_Staff"
}
foreach ($e in $employees) {
    $isManager = @($employees | Where-Object { $_.Manager -eq $e.Username }).Count -gt 0
    $inManagers = (Get-TransitiveGroup $e.Username).ContainsKey('GG_All_Managers')
    Assert-Plan ($isManager -eq $inManagers) "GG_All_Managers: $($e.Username) has direct reports=$isManager but membership=$inManagers"
}

# Computers
foreach ($c in $computers) { Assert-Plan ($ouPaths.ContainsKey($c.OuPath)) "computer $($c.Name): OU '$($c.OuPath)' is not defined" }
Assert-Plan (@($computers | Where-Object { $_.Name -like 'TC-LT-*' }).Count -eq 22) 'computers: expected 22 laptops to pre-stage'

# Folders and permissions
$folderRows | Group-Object Folder | Where-Object Count -gt 1 | ForEach-Object { $script:Failures.Add("folders.csv: duplicate folder '$($_.Name)'") }
foreach ($f in $folders) {
    if ($f.Parent) {
        Assert-Plan ($folderByPath.ContainsKey($f.Parent)) "folders.csv: parent of '$($f.Folder)' is not defined"
        Assert-Plan (-not $f.Share) "folders.csv: '$($f.Folder)' is a subfolder and must not be shared separately"
    }
    else {
        Assert-Plan ([bool]$f.Share) "folders.csv: top-level folder '$($f.Folder)' needs a share name"
    }
    Assert-Plan ($permsByFolder.ContainsKey($f.Folder) -or -not $f.BreakInheritance) "folders.csv: '$($f.Folder)' breaks inheritance but grants nobody access"
}
$shareNames = @($folders | Where-Object { $_.Share } | ForEach-Object { $_.Share })
Assert-Plan ((@($shareNames | Select-Object -Unique)).Count -eq $shareNames.Count) 'folders.csv: share names must be unique'

$usedDl = @{}
foreach ($p in $permissions) {
    $usedDl[$p.Group] = $true
    Assert-Plan ($folderByPath.ContainsKey($p.Folder)) "file-permissions.csv: folder '$($p.Folder)' is not in folders.csv"
    Assert-Plan ($p.Access -in 'RW', 'RO', 'List') "file-permissions.csv: '$($p.Folder)' has invalid access '$($p.Access)'"
    Assert-Plan ($p.Group -like 'DL_FS_*' -and $groupByName.ContainsKey($p.Group)) "AGDLP: '$($p.Folder)' is granted to '$($p.Group)' - permissions go to existing DL_FS_ groups only"
    Assert-Plan ($p.Group -like "*_$($p.Access)") "file-permissions.csv: group '$($p.Group)' grants $($p.Access) - suffix must match"
}
foreach ($g in $groups | Where-Object { $_.Name -like 'DL_FS_*' }) {
    Assert-Plan ($usedDl.ContainsKey($g.Name)) "ad-groups.csv: '$($g.Name)' is not used in file-permissions.csv"
}

# Effective access: generated + explicit expectations
$testCount = 0
foreach ($e in $employees) {
    $folder = $deptByName[$e.Department].DepartmentFolder
    $actual = Get-EffectiveAccess $e.Username $folder
    Assert-Plan ($actual -eq 'RW') "access: $($e.Username) should have RW on own department folder '$folder' but has $actual"
    $company = Get-EffectiveAccess $e.Username 'Company'
    Assert-Plan ($company -in 'RO', 'RW') "access: $($e.Username) cannot read Company"
    $testCount += 2
}
foreach ($t in $accessTests) {
    Assert-Plan ($principals.ContainsKey($t.User)) "access-tests.csv: unknown user '$($t.User)'"
    Assert-Plan ($folderByPath.ContainsKey($t.Folder)) "access-tests.csv: unknown folder '$($t.Folder)'"
    $actual = Get-EffectiveAccess $t.User $t.Folder
    Assert-Plan ($actual -eq $t.Expected) "access-tests.csv: $($t.User) on '$($t.Folder)' expected $($t.Expected), model gives $actual ($($t.Why))"
    $testCount++
}

# GPOs
$gpoByName = @{}
foreach ($g in $gpos) { $gpoByName[$g.Name] = $g }
foreach ($g in $gpos) {
    $isDefault = $g.Name -in 'Default Domain Policy', 'Default Domain Controllers Policy'
    if (-not $isDefault) {
        Assert-Plan ($g.Name -match '^[CU]-[A-Za-z]+-[A-Za-z]+$') "gpo-plan.csv: '$($g.Name)' does not follow <C|U>-<Scope>-<Purpose>"
        Assert-Plan ($g.Name.Substring(0, 1) -eq $g.Type) "gpo-plan.csv: '$($g.Name)' prefix does not match type $($g.Type)"
    }
    Assert-Plan ($g.Type -in 'C', 'U') "gpo-plan.csv: '$($g.Name)' type must be C or U"
    Assert-Plan ($g.Method -in 'Script', 'Manual') "gpo-plan.csv: '$($g.Name)' method must be Script or Manual"
    Assert-Plan ($g.LinkTarget -in '(domain)', 'Domain Controllers' -or $ouPaths.ContainsKey($g.LinkTarget)) "gpo-plan.csv: '$($g.Name)' link target '$($g.LinkTarget)' is not an OU"
    if ($g.Type -eq 'U' -and $g.LinkTarget -ne '(domain)') { Assert-Plan ($g.LinkTarget -like 'TechCorp/Users*') "gpo-plan.csv: user GPO '$($g.Name)' must be linked where the users are" }
    if ($g.Type -eq 'C' -and $g.LinkTarget -like 'TechCorp/*') { Assert-Plan ($g.LinkTarget -like 'TechCorp/Computers*') "gpo-plan.csv: computer GPO '$($g.Name)' must be linked where the computers are" }
    foreach ($s in $g.SecurityFiltering) {
        Assert-Plan ($s -eq 'Authenticated Users' -or $groupByName.ContainsKey($s)) "gpo-plan.csv: '$($g.Name)' filters on unknown group '$s'"
    }
}
foreach ($s in $gpoSettings) {
    if (-not $gpoByName.ContainsKey($s.Gpo)) { $script:Failures.Add("gpo-registry-settings.csv: GPO '$($s.Gpo)' is not in gpo-plan.csv"); continue }
    $g = $gpoByName[$s.Gpo]
    Assert-Plan ($g.Method -eq 'Script') "gpo-registry-settings.csv: '$($s.Gpo)' is Manual in gpo-plan.csv"
    $hive = if ($g.Type -eq 'C') { 'HKLM\' } else { 'HKCU\' }
    Assert-Plan ($s.Key.StartsWith($hive)) "gpo-registry-settings.csv: '$($s.Gpo)' $($s.ValueName) must be under $hive"
    Assert-Plan ($s.Type -in 'DWord', 'String') "gpo-registry-settings.csv: '$($s.Gpo)' $($s.ValueName) type must be DWord or String"
    if ($s.Type -eq 'DWord') { Assert-Plan ($s.Value -match '^\d+$') "gpo-registry-settings.csv: '$($s.Gpo)' $($s.ValueName) DWord value '$($s.Value)' is not a number" }
}
foreach ($g in $gpos | Where-Object Method -eq 'Script') {
    Assert-Plan (@($gpoSettings | Where-Object Gpo -eq $g.Name).Count -gt 0) "gpo-plan.csv: '$($g.Name)' is Script but has no registry settings"
}

Write-Host ("AD plan: {0} OUs | {1} users | {2} admin accounts | {3} groups | {4} computers | {5} folders | {6} ACEs | {7} GPOs | {8} access tests" -f `
    $ous.Count, $users.Count, $adminAccounts.Count, $groups.Count, $computers.Count, $folders.Count, $permissions.Count, $gpos.Count, $testCount)

if ($script:Failures.Count -gt 0) {
    $script:Failures | ForEach-Object { Write-Host "FAIL: $_" -ForegroundColor Red }
    Write-Host "$($script:Failures.Count) check(s) failed, $script:Passed passed." -ForegroundColor Red
    exit 1
}
Write-Host "All $script:Passed AD plan checks passed." -ForegroundColor Green
exit 0
