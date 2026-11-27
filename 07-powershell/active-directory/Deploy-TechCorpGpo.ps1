<#
.SYNOPSIS
    Creates TechCorp's Group Policy Objects, links them, applies security
    filtering and writes their registry-based settings from the repository plan.

.DESCRIPTION
    Reads gpo-plan.csv and gpo-registry-settings.csv through
    Get-TechCorpAdPlan.ps1 and, for every GPO in the plan:
      1. Creates it if missing (comment = settings summary + requirements) and
         disables the unused half (computer GPOs: user settings disabled, and
         the other way round).
      2. Links it to its target OU (or the Domain Controllers OU).
      3. Applies security filtering: when the plan names groups instead of
         Authenticated Users, Authenticated Users is reduced to Read (it must
         keep Read - MS16-072) and the groups get Apply.
      4. Method = Script: writes every registry value with Set-GPRegistryValue.
         Method = Manual: the GPO is created and linked, the settings are
         configured in GPMC following group-policy/gpo-procedures.md (security
         templates, Group Policy Preferences and audit policy cannot be set
         with the GroupPolicy module).

    The two default GPOs are never created or linked by this script - only
    reported. Blocks inheritance on the Disabled OU.

    With -PrepareLaps it also extends the schema for Windows LAPS and grants
    the computer self-permission and the read permission on the OUs.

    Run on TC-DC01 as adm-eren.yeager after Deploy-TechCorpAd.ps1. Supports -WhatIf.

.PARAMETER PrepareLaps
    Run the one-time Windows LAPS AD preparation (schema + permissions).

.PARAMETER Server
    Domain controller to target (default: PDC emulator).

.EXAMPLE
    .\Deploy-TechCorpGpo.ps1 -WhatIf

.EXAMPLE
    .\Deploy-TechCorpGpo.ps1 -PrepareLaps
#>
#Requires -Modules ActiveDirectory, GroupPolicy
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$PrepareLaps,

    [string]$Server
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$plan = & (Join-Path $PSScriptRoot 'Get-TechCorpAdPlan.ps1')
$domain = Get-ADDomain
if (-not $Server) { $Server = $domain.PDCEmulator }
$gp = @{ Server = $Server; Domain = $domain.DNSRoot }
$netbios = $domain.NetBIOSName

$ouDn = @{}
foreach ($o in $plan.OUs) { $ouDn[$o.Path] = $o.DistinguishedName }

function Write-Step([string]$Step, [string]$Object, [string]$Result) {
    Write-Host ('{0,-10} {1,-36} {2}' -f $Step, $Object, $Result)
}

function Get-LinkTargetDn([string]$LinkTarget) {
    switch ($LinkTarget) {
        '(domain)' { return $domain.DistinguishedName }
        'Domain Controllers' { return $domain.DomainControllersContainer }
        default { return $ouDn[$LinkTarget] }
    }
}

foreach ($g in $plan.Gpos) {
    $target = Get-LinkTargetDn $g.LinkTarget
    if ($g.Name -like 'Default Domain*') {
        Write-Step 'Default' $g.Name "manual - $($g.Settings)"
        continue
    }

    # 1. Create
    $gpo = Get-GPO -Name $g.Name @gp -ErrorAction SilentlyContinue
    if (-not $gpo) {
        if (-not $PSCmdlet.ShouldProcess($g.Name, 'Create GPO')) { continue }
        $gpo = New-GPO -Name $g.Name -Comment "$($g.Settings) | $($g.Requirements)" @gp
        $gpo.GpoStatus = $(if ($g.Type -eq 'C') { 'UserSettingsDisabled' } else { 'ComputerSettingsDisabled' })
        Write-Step 'GPO' $g.Name 'created'
    }
    else { Write-Step 'GPO' $g.Name 'exists' }

    # 2. Link
    $links = @((Get-GPInheritance -Target $target @gp).GpoLinks | ForEach-Object { $_.DisplayName })
    if ($g.Name -notin $links -and $PSCmdlet.ShouldProcess($target, "Link $($g.Name)")) {
        $null = New-GPLink -Name $g.Name -Target $target -LinkEnabled Yes @gp
        Write-Step 'Link' $g.Name "linked to $($g.LinkTarget)"
    }

    # 3. Security filtering
    $filters = @($g.SecurityFiltering | Where-Object { $_ -ne 'Authenticated Users' })
    if ($filters.Count -gt 0) {
        $authUsers = Get-GPPermission -Name $g.Name -TargetName 'Authenticated Users' -TargetType Group @gp -ErrorAction SilentlyContinue
        if ((-not $authUsers -or $authUsers.Permission -ne 'GpoRead') -and $PSCmdlet.ShouldProcess($g.Name, 'Authenticated Users: Read only')) {
            $null = Set-GPPermission -Name $g.Name -TargetName 'Authenticated Users' -TargetType Group -PermissionLevel GpoRead -Replace @gp
            Write-Step 'Filter' $g.Name 'Authenticated Users = Read'
        }
        foreach ($f in $filters) {
            $perm = Get-GPPermission -Name $g.Name -TargetName "$netbios\$f" -TargetType Group @gp -ErrorAction SilentlyContinue
            if ((-not $perm -or $perm.Permission -ne 'GpoApply') -and $PSCmdlet.ShouldProcess($g.Name, "$f = Apply")) {
                $null = Set-GPPermission -Name $g.Name -TargetName "$netbios\$f" -TargetType Group -PermissionLevel GpoApply @gp
                Write-Step 'Filter' $g.Name "$f = Apply"
            }
        }
    }

    # 4. Settings
    if ($g.Method -ne 'Script') { Write-Step 'Settings' $g.Name 'manual - see gpo-procedures.md'; continue }
    foreach ($s in $plan.GpoSettings | Where-Object Gpo -eq $g.Name) {
        $value = if ($s.Type -eq 'DWord') { [int]$s.Value } else { [string]$s.Value }
        $current = $null
        try { $current = Get-GPRegistryValue -Name $g.Name -Key $s.Key -ValueName $s.ValueName @gp } catch { $current = $null }
        if ($current -and [string]$current.Value -eq [string]$value) { continue }
        if ($PSCmdlet.ShouldProcess($g.Name, "$($s.Key)\$($s.ValueName) = $value")) {
            $null = Set-GPRegistryValue -Name $g.Name -Key $s.Key -ValueName $s.ValueName -Type $s.Type -Value $value @gp
            Write-Step 'Setting' $g.Name "$($s.ValueName) = $value"
        }
    }
}

# Disabled OU: no policy reaches leavers' accounts
$disabledDn = $ouDn['TechCorp/Disabled']
if (-not (Get-GPInheritance -Target $disabledDn @gp).GpoInheritanceBlocked -and $PSCmdlet.ShouldProcess($disabledDn, 'Block inheritance')) {
    $null = Set-GPInheritance -Target $disabledDn -IsBlocked Yes @gp
    Write-Step 'Inherit' 'TechCorp/Disabled' 'blocked'
}

# Windows LAPS one-time AD preparation
if ($PrepareLaps -and $PSCmdlet.ShouldProcess($domain.DNSRoot, 'Windows LAPS: extend schema and set OU permissions')) {
    Update-LapsADSchema -Confirm:$false
    $null = Set-LapsADComputerSelfPermission -Identity $ouDn['TechCorp/Computers']
    $null = Set-LapsADReadPasswordPermission -Identity $ouDn['TechCorp/Computers/Workstations'] -AllowedPrincipals "$netbios\GG_IT_WorkstationAdmins"
    $null = Set-LapsADResetPasswordPermission -Identity $ouDn['TechCorp/Computers/Workstations'] -AllowedPrincipals "$netbios\GG_IT_WorkstationAdmins"
    Write-Step 'LAPS' $domain.DNSRoot 'schema extended, self-permission + read/reset delegated'
}
Write-Host 'Done. Configure the Manual GPOs in GPMC, then verify with gpresult and Test-TechCorpAd.ps1.'
