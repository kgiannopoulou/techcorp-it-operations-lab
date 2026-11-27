<#
.SYNOPSIS
    Builds TechCorp's folder tree, NTFS permissions, SMB shares and (optionally)
    the DFS namespace on TC-FS01 from the repository plan.

.DESCRIPTION
    Reads folders.csv and file-permissions.csv through Get-TechCorpAdPlan.ps1 and:
      1. Creates <DataRoot> with a protected ACL: Administrators + SYSTEM only.
      2. Creates every folder and makes its EXPLICIT ACL match the plan exactly
         (explicit entries that are not in the plan are removed - the CSV is the
         source of truth). Inherited entries are left alone unless the folder
         breaks inheritance.
      3. Shares each top-level folder: Administrators Full, Authenticated Users
         Change, access-based enumeration ON. NTFS is the real control.
      4. With -CreateNamespace: domain-based namespace \\<domain>\dfs with one
         folder per share.

    How the access levels are written (no Deny entries are ever used):
      RW   - Modify on subfolders and files, plus read/create on the folder
             itself WITHOUT Delete, so users cannot delete or rename the
             department root folder.
      RO   - Read & execute, inherited by everything below.
      List - Read & execute on this folder only (browse the root, nothing more).

    Run on TC-FS01 as adm-eren.yeager after Deploy-TechCorpAd.ps1 (the DL_FS_
    groups must exist). Supports -WhatIf.

.PARAMETER DataRoot
    Local root of the data volume (default D:\Shares).

.PARAMETER NetBiosDomain
    NetBIOS domain name used to resolve groups (default TECHCORP).

.PARAMETER CreateNamespace
    Also create the domain-based DFS namespace and its folders (needs the
    FS-DFS-Namespace role and the DFSN module).

.PARAMETER NamespaceServer
    Server that hosts the namespace root share (default TC-FS01).

.EXAMPLE
    .\Deploy-TechCorpFileShare.ps1 -WhatIf

.EXAMPLE
    .\Deploy-TechCorpFileShare.ps1 -CreateNamespace
#>
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DataRoot = 'D:\Shares',

    [string]$NetBiosDomain = 'TECHCORP',

    [switch]$CreateNamespace,

    [string]$NamespaceServer = 'TC-FS01'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$plan = & (Join-Path $PSScriptRoot 'Get-TechCorpAdPlan.ps1')
$Admins = 'BUILTIN\Administrators'
$System = 'NT AUTHORITY\SYSTEM'
$AuthUsers = 'NT AUTHORITY\Authenticated Users'
$fsr = [System.Security.AccessControl.FileSystemAccessRule]

function ConvertTo-AccessRule([string]$Identity, [string]$Access) {
    switch ($Access) {
        'Full' { return @($fsr::new($Identity, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')) }
        'RW' {
            return @(
                $fsr::new($Identity, 'Modify', 'ContainerInherit, ObjectInherit', 'InheritOnly', 'Allow'),
                $fsr::new($Identity, 'ReadAndExecute, CreateFiles, CreateDirectories, WriteAttributes, WriteExtendedAttributes', 'None', 'None', 'Allow')
            )
        }
        'RO' { return @($fsr::new($Identity, 'ReadAndExecute', 'ContainerInherit, ObjectInherit', 'None', 'Allow')) }
        'List' { return @($fsr::new($Identity, 'ReadAndExecute', 'None', 'None', 'Allow')) }
        default { throw "Unknown access level '$Access'" }
    }
}

function Write-Step([string]$Step, [string]$Object, [string]$Result) {
    Write-Host ('{0,-10} {1,-40} {2}' -f $Step, $Object, $Result)
}

# 1. Data root -------------------------------------------------------------
if (-not (Test-Path -LiteralPath $DataRoot) -and $PSCmdlet.ShouldProcess($DataRoot, 'Create data root')) {
    $null = New-Item -ItemType Directory -Path $DataRoot
}
if ((Test-Path -LiteralPath $DataRoot) -and $PSCmdlet.ShouldProcess($DataRoot, 'Set protected ACL (Administrators, SYSTEM)')) {
    # Fresh DACL: drops the volume defaults (e.g. Users: create folders) instead of editing them
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($id in $Admins, $System) { foreach ($r in ConvertTo-AccessRule $id 'Full') { $acl.AddAccessRule($r) } }
    Set-Acl -LiteralPath $DataRoot -AclObject $acl
    Write-Step 'Root' $DataRoot 'ACL set (Administrators, SYSTEM)'
}

# 2. Folders and NTFS ------------------------------------------------------
$byFolder = @{}
foreach ($p in $plan.Permissions) {
    if (-not $byFolder.ContainsKey($p.Folder)) { $byFolder[$p.Folder] = @() }
    $byFolder[$p.Folder] += $p
}

foreach ($f in ($plan.Folders | Sort-Object { $_.Folder.Split('\').Count })) {
    $path = Join-Path $DataRoot $f.Folder
    if (-not (Test-Path -LiteralPath $path) -and $PSCmdlet.ShouldProcess($path, 'Create folder')) {
        $null = New-Item -ItemType Directory -Path $path
        Write-Step 'Folder' $f.Folder 'created'
    }
    if (-not (Test-Path -LiteralPath $path)) { continue }   # -WhatIf run

    $planned = @()
    if ($byFolder.ContainsKey($f.Folder)) { $planned = $byFolder[$f.Folder] }
    $what = ($planned | ForEach-Object { "$($_.Group)=$($_.Access)" }) -join ', '
    if (-not $PSCmdlet.ShouldProcess($path, "Set ACL: break inheritance=$($f.BreakInheritance); $what")) { continue }

    $acl = Get-Acl -LiteralPath $path
    if ($f.BreakInheritance) { $acl.SetAccessRuleProtection($true, $false) } else { $acl.SetAccessRuleProtection($false, $true) }
    foreach ($r in @($acl.Access | Where-Object { -not $_.IsInherited })) { $null = $acl.RemoveAccessRule($r) }
    if ($f.BreakInheritance) {
        foreach ($id in $Admins, $System) { foreach ($r in ConvertTo-AccessRule $id 'Full') { $acl.AddAccessRule($r) } }
    }
    foreach ($p in $planned) {
        foreach ($r in ConvertTo-AccessRule "$NetBiosDomain\$($p.Group)" $p.Access) { $acl.AddAccessRule($r) }
    }
    Set-Acl -LiteralPath $path -AclObject $acl
    Write-Step 'NTFS' $f.Folder $(if ($what) { $what } else { 'inherits only' })
}

# 3. SMB shares ------------------------------------------------------------
foreach ($f in $plan.Folders | Where-Object Share) {
    $path = Join-Path $DataRoot $f.Folder
    $share = Get-SmbShare -Name $f.Share -ErrorAction SilentlyContinue
    if (-not $share) {
        if ($PSCmdlet.ShouldProcess($f.Share, "Share $path")) {
            $null = New-SmbShare -Name $f.Share -Path $path -FullAccess $Admins -ChangeAccess $AuthUsers `
                -FolderEnumerationMode AccessBased -Description $f.Description
            Write-Step 'Share' $f.Share 'created (ABE on)'
        }
    }
    elseif ($share.FolderEnumerationMode -ne 'AccessBased' -and $PSCmdlet.ShouldProcess($f.Share, 'Enable access-based enumeration')) {
        Set-SmbShare -Name $f.Share -FolderEnumerationMode AccessBased -Force
        Write-Step 'Share' $f.Share 'updated (ABE on)'
    }
    else { Write-Step 'Share' $f.Share 'exists' }
}

# 4. DFS namespace ---------------------------------------------------------
if ($CreateNamespace) {
    $nsRoot = "\\$($plan.DomainFqdn)\dfs"
    $nsLocal = Join-Path (Split-Path -Path $DataRoot -Qualifier) 'DFSRoots\dfs'
    if (-not (Test-Path -LiteralPath $nsLocal) -and $PSCmdlet.ShouldProcess($nsLocal, 'Create namespace root folder')) {
        $null = New-Item -ItemType Directory -Path $nsLocal
    }
    if (-not (Get-SmbShare -Name 'dfs' -ErrorAction SilentlyContinue) -and $PSCmdlet.ShouldProcess('dfs', "Share $nsLocal")) {
        $null = New-SmbShare -Name 'dfs' -Path $nsLocal -FullAccess $Admins -ReadAccess $AuthUsers -Description 'DFS namespace root'
    }
    if (-not (Get-DfsnRoot -Path $nsRoot -ErrorAction SilentlyContinue) -and $PSCmdlet.ShouldProcess($nsRoot, 'Create domain-based namespace')) {
        $null = New-DfsnRoot -Path $nsRoot -TargetPath "\\$NamespaceServer\dfs" -Type DomainV2
        Write-Step 'DFS' $nsRoot 'created'
    }
    foreach ($f in $plan.Folders | Where-Object Share) {
        $nsFolder = "$nsRoot\$($f.Share.TrimEnd('$'))"
        if (-not (Get-DfsnFolder -Path $nsFolder -ErrorAction SilentlyContinue) -and $PSCmdlet.ShouldProcess($nsFolder, "Target \\$NamespaceServer\$($f.Share)")) {
            $null = New-DfsnFolder -Path $nsFolder -TargetPath "\\$NamespaceServer\$($f.Share)"
            Write-Step 'DFS' $nsFolder 'created'
        }
    }
}
Write-Host 'Done. Verify with Test-TechCorpAd.ps1 -FileServer TC-FS01.'
