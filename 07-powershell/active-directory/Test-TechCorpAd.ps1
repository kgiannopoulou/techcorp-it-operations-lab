<#
.SYNOPSIS
    Verifies the live TechCorp domain against the repository plan and prints
    PASS / FAIL / SKIP per check. Read-only.

.DESCRIPTION
    Compares Active Directory (and optionally TC-FS01) with the plan from
    Get-TechCorpAdPlan.ps1:
      Domain   - functional level, Recycle Bin, machine account quota,
                 default password policy, both domain controllers, FSMO holder
      OUs      - exist and are protected from accidental deletion
      Groups   - exist, correct scope and OU, direct members exactly as planned
      Users    - exist, enabled, correct OU, title/department/manager
      Admins   - OU, built-in groups, not delegable, PSO-AdminAccounts applied
      Computers- in the planned OU once joined (SKIP until they are)
      GPOs     - exist, linked to the planned target, registry values as planned,
                 security filtering
      Files    - (with -FileServer) NTFS inheritance and explicit entries per
                 folder, shares with access-based enumeration

    Use the CSV output as lab evidence (16-reports/).

.PARAMETER FileServer
    Also check folders and shares on this server (e.g. TC-FS01) through its
    administrative share.

.PARAMETER DataRoot
    Local data root on the file server (default D:\Shares).

.PARAMETER Server
    Domain controller to query (default: any DC).

.PARAMETER OutputPath
    Optional CSV path for the results.

.EXAMPLE
    .\Test-TechCorpAd.ps1

.EXAMPLE
    .\Test-TechCorpAd.ps1 -FileServer TC-FS01 -OutputPath .\output\ad-20270118.csv
#>
#Requires -Modules ActiveDirectory
[CmdletBinding()]
param(
    [string]$FileServer,

    [string]$DataRoot = 'D:\Shares',

    [string]$Server,

    [string]$OutputPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$plan = & (Join-Path $PSScriptRoot 'Get-TechCorpAdPlan.ps1')
$adParams = @{}
if ($Server) { $adParams['Server'] = $Server }

$script:Results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$Area, [string]$Check, [string]$Status, [string]$Detail = '') {
    $script:Results.Add([pscustomobject]@{ Area = $Area; Check = $Check; Status = $Status; Detail = $Detail })
}
function Test-Check([string]$Area, [string]$Check, [bool]$Condition, [string]$Detail = '') {
    Add-Result $Area $Check $(if ($Condition) { 'PASS' } else { 'FAIL' }) $Detail
}
function Get-ParentDn([string]$DistinguishedName) { return ($DistinguishedName -replace '^.+?(?<!\\),', '') }
function Compare-Set([string[]]$Expected, [string[]]$Actual) {
    $missing = @($Expected | Where-Object { $_ -notin $Actual })
    $extra = @($Actual | Where-Object { $_ -notin $Expected })
    $parts = @()
    if ($missing.Count) { $parts += "missing: $($missing -join ', ')" }
    if ($extra.Count) { $parts += "unexpected: $($extra -join ', ')" }
    return ($parts -join '; ')
}

# Domain ---------------------------------------------------------------------
$domain = Get-ADDomain @adParams
$forest = Get-ADForest @adParams
Test-Check 'Domain' 'Domain DN matches plan' ($domain.DistinguishedName -eq $plan.DomainDn) $domain.DistinguishedName
Test-Check 'Domain' 'Domain functional level >= 2016' ([string]$domain.DomainMode -match '201[6-9]|202\d') ([string]$domain.DomainMode)
$recycle = Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'" @adParams
Test-Check 'Domain' 'AD Recycle Bin enabled' (@($recycle.EnabledScopes).Count -gt 0)
$maq = (Get-ADObject -Identity $domain.DistinguishedName -Properties 'ms-DS-MachineAccountQuota' @adParams).'ms-DS-MachineAccountQuota'
Test-Check 'Domain' 'ms-DS-MachineAccountQuota = 0' ($maq -eq 0) "value $maq"
$pw = Get-ADDefaultDomainPasswordPolicy @adParams
Test-Check 'Domain' 'Default policy: min length >= 14' ($pw.MinPasswordLength -ge 14) "$($pw.MinPasswordLength)"
Test-Check 'Domain' 'Default policy: complexity on' ([bool]$pw.ComplexityEnabled)
Test-Check 'Domain' 'Default policy: lockout threshold 10' ($pw.LockoutThreshold -eq 10) "$($pw.LockoutThreshold)"
$dcs = @(Get-ADDomainController -Filter * @adParams | ForEach-Object { $_.Name })
foreach ($dc in 'TC-DC01', 'TC-DC02') {
    Test-Check 'Domain' "Domain controller $dc" ($dc -in $dcs) ($dcs -join ', ')
}
Test-Check 'Domain' 'FSMO roles on TC-DC01' (($domain.PDCEmulator -like 'TC-DC01.*') -and ($domain.RIDMaster -like 'TC-DC01.*') -and ($forest.SchemaMaster -like 'TC-DC01.*')) "PDC $($domain.PDCEmulator)"

# OUs ------------------------------------------------------------------------
foreach ($ou in $plan.OUs) {
    $o = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$($ou.DistinguishedName)'" -Properties ProtectedFromAccidentalDeletion @adParams
    if (-not $o) { Add-Result 'OU' $ou.Path 'FAIL' 'missing'; continue }
    Test-Check 'OU' $ou.Path ([bool]$o.ProtectedFromAccidentalDeletion) 'protected from accidental deletion'
}

# Groups ---------------------------------------------------------------------
foreach ($g in $plan.Groups) {
    $ad = Get-ADGroup -Filter "Name -eq '$($g.Name)'" @adParams
    if (-not $ad) { Add-Result 'Group' $g.Name 'FAIL' 'missing'; continue }
    $members = @(Get-ADGroupMember -Identity $ad.DistinguishedName @adParams | ForEach-Object { $_.SamAccountName })
    $diff = Compare-Set $g.Members $members
    $ok = ($ad.GroupScope.ToString() -eq $g.Scope) -and ((Get-ParentDn $ad.DistinguishedName) -eq $g.OuDn) -and (-not $diff)
    Test-Check 'Group' $g.Name $ok $(if ($diff) { $diff } else { "$($ad.GroupScope), $($members.Count) member(s)" })
}

# Users ----------------------------------------------------------------------
foreach ($u in $plan.Users) {
    $ad = Get-ADUser -Filter "SamAccountName -eq '$($u.SamAccountName)'" -Properties Title, Department, Manager, EmployeeID @adParams
    if (-not $ad) { Add-Result 'User' $u.SamAccountName 'FAIL' 'missing'; continue }
    $problems = @()
    if (-not $ad.Enabled) { $problems += 'disabled' }
    if ((Get-ParentDn $ad.DistinguishedName) -ne $u.OuDn) { $problems += "OU $(Get-ParentDn $ad.DistinguishedName)" }
    if ($ad.Title -ne $u.Title) { $problems += "title '$($ad.Title)'" }
    if ($ad.Department -ne $u.Department) { $problems += "department '$($ad.Department)'" }
    if ($ad.UserPrincipalName -ne $u.UserPrincipalName) { $problems += "UPN $($ad.UserPrincipalName)" }
    if ($u.Manager) {
        $mgr = Get-ADUser -Filter "SamAccountName -eq '$($u.Manager)'" @adParams
        if (-not $mgr -or $ad.Manager -ne $mgr.DistinguishedName) { $problems += "manager should be $($u.Manager)" }
    }
    Test-Check 'User' $u.SamAccountName ($problems.Count -eq 0) ($problems -join '; ')
}

# Privileged accounts --------------------------------------------------------
foreach ($a in $plan.AdminAccounts) {
    $ad = Get-ADUser -Filter "SamAccountName -eq '$($a.SamAccountName)'" -Properties AccountNotDelegated, MemberOf @adParams
    if (-not $ad) { Add-Result 'Admin' $a.SamAccountName 'FAIL' 'missing'; continue }
    $problems = @()
    if ((Get-ParentDn $ad.DistinguishedName) -ne $a.OuDn) { $problems += 'wrong OU' }
    if (-not $ad.AccountNotDelegated) { $problems += 'delegable' }
    $memberOf = @($ad.MemberOf | ForEach-Object { (Get-ADGroup -Identity $_ @adParams).Name })
    foreach ($b in $a.BuiltInGroups) { if ($b -notin $memberOf) { $problems += "not in $b" } }
    if ($a.SamAccountName -like 'wadm-*' -and 'Domain Admins' -in $memberOf) { $problems += 'workstation admin is a Domain Admin' }
    $pso = Get-ADUserResultantPasswordPolicy -Identity $ad.DistinguishedName @adParams
    if (-not $pso -or $pso.Name -ne 'PSO-AdminAccounts') { $problems += 'PSO-AdminAccounts not applied' }
    Test-Check 'Admin' $a.SamAccountName ($problems.Count -eq 0) ($problems -join '; ')
}

# Computers ------------------------------------------------------------------
foreach ($c in $plan.Computers) {
    $ad = Get-ADComputer -Filter "Name -eq '$($c.Name)'" @adParams
    if (-not $ad) { Add-Result 'Computer' $c.Name 'SKIP' 'not joined yet'; continue }
    Test-Check 'Computer' $c.Name ((Get-ParentDn $ad.DistinguishedName) -eq $c.OuDn) "expected $($c.OuPath)"
}

# GPOs -----------------------------------------------------------------------
if (Get-Module -ListAvailable -Name GroupPolicy) {
    Import-Module GroupPolicy
    $gp = @{ Domain = $domain.DNSRoot }
    if ($Server) { $gp['Server'] = $Server }
    $ouDn = @{}
    foreach ($o in $plan.OUs) { $ouDn[$o.Path] = $o.DistinguishedName }
    foreach ($g in $plan.Gpos) {
        $gpo = Get-GPO -Name $g.Name @gp -ErrorAction SilentlyContinue
        if (-not $gpo) { Add-Result 'GPO' $g.Name 'FAIL' 'missing'; continue }
        $target = switch ($g.LinkTarget) { '(domain)' { $domain.DistinguishedName } 'Domain Controllers' { $domain.DomainControllersContainer } default { $ouDn[$g.LinkTarget] } }
        $links = @((Get-GPInheritance -Target $target @gp).GpoLinks | ForEach-Object { $_.DisplayName })
        Test-Check 'GPO' "$($g.Name) linked" ($g.Name -in $links) $g.LinkTarget
        foreach ($s in $plan.GpoSettings | Where-Object Gpo -eq $g.Name) {
            $v = $null
            try { $v = Get-GPRegistryValue -Name $g.Name -Key $s.Key -ValueName $s.ValueName @gp } catch { $v = $null }
            Test-Check 'GPO' "$($g.Name): $($s.ValueName)" ($v -and [string]$v.Value -eq $s.Value) $(if ($v) { "value $($v.Value)" } else { 'not set' })
        }
        foreach ($f in $g.SecurityFiltering | Where-Object { $_ -ne 'Authenticated Users' }) {
            $p = Get-GPPermission -Name $g.Name -TargetName $f -TargetType Group @gp -ErrorAction SilentlyContinue
            Test-Check 'GPO' "$($g.Name): $f = Apply" ($p -and [string]$p.Permission -eq 'GpoApply')
        }
        if (@($g.SecurityFiltering | Where-Object { $_ -ne 'Authenticated Users' }).Count -gt 0) {
            $p = Get-GPPermission -Name $g.Name -TargetName 'Authenticated Users' -TargetType Group @gp -ErrorAction SilentlyContinue
            Test-Check 'GPO' "$($g.Name): Authenticated Users = Read (MS16-072)" ($p -and [string]$p.Permission -eq 'GpoRead') $(if ($p) { [string]$p.Permission } else { 'no entry - computers cannot read the GPO' })
        }
    }
}
else { Add-Result 'GPO' 'GroupPolicy module' 'SKIP' 'install GPMC / RSAT to check GPOs' }

# File server ----------------------------------------------------------------
if ($FileServer) {
    $netbios = $domain.NetBIOSName
    $unc = "\\$FileServer\$($DataRoot -replace '^([A-Za-z]):', '${1}$$')"
    $byFolder = @{}
    foreach ($p in $plan.Permissions) {
        if (-not $byFolder.ContainsKey($p.Folder)) { $byFolder[$p.Folder] = @() }
        $byFolder[$p.Folder] += $p
    }
    foreach ($f in $plan.Folders) {
        $path = Join-Path $unc $f.Folder
        if (-not (Test-Path -LiteralPath $path)) { Add-Result 'NTFS' $f.Folder 'FAIL' "missing $path"; continue }
        $acl = Get-Acl -LiteralPath $path
        $explicit = @($acl.Access | Where-Object { -not $_.IsInherited } | ForEach-Object { $_.IdentityReference.Value } |
            Where-Object { $_ -notin 'BUILTIN\Administrators', 'NT AUTHORITY\SYSTEM' } | Select-Object -Unique)
        $expected = @()
        if ($byFolder.ContainsKey($f.Folder)) { $expected = @($byFolder[$f.Folder] | ForEach-Object { "$netbios\$($_.Group)" }) }
        $diff = Compare-Set $expected $explicit
        $inheritOk = ($acl.AreAccessRulesProtected -eq $f.BreakInheritance)
        Test-Check 'NTFS' $f.Folder ($inheritOk -and -not $diff) $(if (-not $inheritOk) { "inheritance protected=$($acl.AreAccessRulesProtected), plan BreakInheritance=$($f.BreakInheritance)" } elseif ($diff) { $diff } else { ($expected -join ', ') })
    }
    foreach ($f in $plan.Folders | Where-Object Share) {
        $share = Get-SmbShare -CimSession $FileServer -Name $f.Share -ErrorAction SilentlyContinue
        if (-not $share) { Add-Result 'Share' $f.Share 'FAIL' 'missing'; continue }
        Test-Check 'Share' $f.Share ([string]$share.FolderEnumerationMode -eq 'AccessBased') "ABE $($share.FolderEnumerationMode)"
    }
}
else { Add-Result 'NTFS' 'File server checks' 'SKIP' 'use -FileServer TC-FS01' }

# Output ---------------------------------------------------------------------
$script:Results | Format-Table -AutoSize -Wrap
$counts = $script:Results | Group-Object Status | ForEach-Object { "$($_.Name) $($_.Count)" }
Write-Host ($counts -join ' | ')
if ($OutputPath) {
    $script:Results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "Results written to $OutputPath"
}
if (@($script:Results | Where-Object Status -eq 'FAIL').Count -gt 0) { exit 1 }
exit 0
