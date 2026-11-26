<#
.SYNOPSIS
    Validates the repository's source data and internal Markdown links.

.DESCRIPTION
    Checks that the CSV "single sources of truth" are consistent with each other:
      - 00-company-overview/data/employees.csv
      - 01-office-deployment/equipment-inventory/hardware-inventory.csv
      - 02-network-infrastructure/ip-addressing/vlan-subnets.csv
      - 02-network-infrastructure/switching/switch-port-plan.csv (+ tc-sw01.cfg)
    and that every relative link in every Markdown file points to a file that exists.

    Runs on Windows PowerShell 5.1 and PowerShell 7+ (used by GitHub Actions).

.EXAMPLE
    ./.github/scripts/Test-RepoData.ps1
    Exit code 0 = all checks passed, 1 = at least one failure.
#>
[CmdletBinding()]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
)

$ErrorActionPreference = 'Stop'
$script:Failures = New-Object System.Collections.Generic.List[string]

function Add-Failure([string]$Message) { $script:Failures.Add($Message) }

function ConvertTo-UInt32Ip([string]$Ip) {
    $bytes = ([System.Net.IPAddress]::Parse($Ip)).GetAddressBytes()
    [Array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function Test-IpInSubnet([string]$Ip, [string]$Cidr) {
    $net, $len = $Cidr.Split('/')
    $mask = if ([int]$len -eq 0) { [uint32]0 } else { [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - [int]$len)) }
    return ((ConvertTo-UInt32Ip $Ip) -band $mask) -eq ((ConvertTo-UInt32Ip $net) -band $mask)
}

$employeesPath = Join-Path $Root '00-company-overview/data/employees.csv'
$inventoryPath = Join-Path $Root '01-office-deployment/equipment-inventory/hardware-inventory.csv'
$vlanPath      = Join-Path $Root '02-network-infrastructure/ip-addressing/vlan-subnets.csv'

$employees = @(Import-Csv $employeesPath)
$inventory = @(Import-Csv $inventoryPath)
$vlans     = @(Import-Csv $vlanPath)

# ---------- Employees ----------
if ($employees.Count -ne 20) { Add-Failure "employees.csv: expected 20 employees, found $($employees.Count)" }

foreach ($col in 'EmployeeID', 'Username', 'AssetTag') {
    $employees | Group-Object $col | Where-Object Count -gt 1 | ForEach-Object {
        Add-Failure "employees.csv: duplicate $col '$($_.Name)'"
    }
}

$usernames = @{}
$employees | ForEach-Object { $usernames[$_.Username] = $_ }

foreach ($e in $employees) {
    $expected = ('{0}.{1}' -f $e.FirstName, $e.LastName).ToLowerInvariant()
    if ($e.Username -ne $expected) { Add-Failure "employees.csv: $($e.EmployeeID) username '$($e.Username)' should be '$expected'" }
    if ($e.Username.Length -gt 20) { Add-Failure "employees.csv: $($e.Username) exceeds 20 characters (sAMAccountName limit)" }
    if ($e.Manager -and -not $usernames.ContainsKey($e.Manager)) { Add-Failure "employees.csv: $($e.EmployeeID) manager '$($e.Manager)' does not exist" }
}

# ---------- Inventory ----------
$inventory | Group-Object AssetTag | Where-Object Count -gt 1 | ForEach-Object {
    Add-Failure "hardware-inventory.csv: duplicate AssetTag '$($_.Name)'"
}

$byTag = @{}
$inventory | ForEach-Object { $byTag[$_.AssetTag] = $_ }

foreach ($e in $employees) {
    $asset = $byTag[$e.AssetTag]
    if (-not $asset) { Add-Failure "inventory: employee $($e.Username) has laptop $($e.AssetTag) which is not in the inventory"; continue }
    if ($asset.AssignedTo -ne $e.Username) { Add-Failure "inventory: $($e.AssetTag) is assigned to '$($asset.AssignedTo)' but employees.csv says '$($e.Username)'" }
}

foreach ($a in $inventory) {
    if ($a.Hostname -and $a.Hostname.Length -gt 15) { Add-Failure "inventory: hostname '$($a.Hostname)' exceeds 15 characters (NetBIOS limit)" }
    if ($a.Hostname -and $a.Hostname -cne $a.Hostname.ToUpperInvariant()) { Add-Failure "inventory: hostname '$($a.Hostname)' must be upper-case" }
    if ($a.AssetTag -notmatch '^TC-[A-Z0-9]+(-\d{3})?$') { Add-Failure "inventory: asset tag '$($a.AssetTag)' does not follow naming convention" }
}

# ---------- IP plan ----------
$subnetByVlan = @{}
foreach ($v in $vlans) { if ($v.Subnet -match '/') { $subnetByVlan[$v.VLAN] = $v.Subnet } }

$static = @($inventory | Where-Object { $_.IPAddress -match '^\d+\.\d+\.\d+\.\d+$' })
$static | Group-Object IPAddress | Where-Object Count -gt 1 | ForEach-Object {
    Add-Failure "inventory: IP $($_.Name) used by more than one asset ($(($_.Group.AssetTag) -join ', '))"
}
foreach ($a in $static) {
    $cidr = $subnetByVlan[$a.VLAN]
    if (-not $cidr) { Add-Failure "inventory: $($a.AssetTag) is on VLAN '$($a.VLAN)' which is not defined in vlan-subnets.csv"; continue }
    if (-not (Test-IpInSubnet $a.IPAddress $cidr)) { Add-Failure "inventory: $($a.AssetTag) IP $($a.IPAddress) is outside VLAN $($a.VLAN) subnet $cidr" }
}

# ---------- Switch port plan vs VLANs, inventory and generated config ----------
$portPlanPath = Join-Path $Root '02-network-infrastructure/switching/switch-port-plan.csv'
$switchCfgPath = Join-Path $Root '02-network-infrastructure/switching/tc-sw01.cfg'
$ports = @(Import-Csv $portPlanPath)
$validVlans = @($vlans | ForEach-Object { $_.VLAN })
if ($ports.Count -ne 48) { Add-Failure "switch-port-plan.csv: expected 48 ports, found $($ports.Count)" }
$ports | Group-Object Port | Where-Object Count -gt 1 | ForEach-Object { Add-Failure "switch-port-plan.csv: duplicate port $($_.Name)" }

$cfgText = Get-Content -Raw -Encoding UTF8 $switchCfgPath
$cfgBlocks = @{}
foreach ($m in [regex]::Matches($cfgText, '(?ms)^interface (Gi1/0/\d+)\r?\n(.*?)^!')) { $cfgBlocks[$m.Groups[1].Value] = $m.Groups[2].Value }

foreach ($p in $ports) {
    if ($p.Mode -notin 'access', 'trunk', 'lacp') { Add-Failure "switch-port-plan.csv: port $($p.Port) has invalid mode '$($p.Mode)'"; continue }
    $used = @()
    if ($p.Mode -eq 'trunk') { $used += $p.NativeVLAN; $used += $p.AllowedVLANs.Split(',') } else { $used += $p.AccessVLAN }
    foreach ($v in $used) { if ($v -notin $validVlans) { Add-Failure "switch-port-plan.csv: port $($p.Port) uses VLAN '$v' not defined in vlan-subnets.csv" } }
    if ($p.Device -and -not $byTag.ContainsKey($p.Device)) { Add-Failure "switch-port-plan.csv: port $($p.Port) device '$($p.Device)' is not in hardware-inventory.csv" }

    $block = $cfgBlocks[$p.Interface]
    if (-not $block) { Add-Failure "tc-sw01.cfg: no 'interface $($p.Interface)' block"; continue }
    if ($p.Mode -eq 'trunk') {
        if ($block -notmatch "switchport trunk allowed vlan $([regex]::Escape($p.AllowedVLANs))\s") { Add-Failure "tc-sw01.cfg: $($p.Interface) allowed VLANs differ from port plan ($($p.AllowedVLANs))" }
        if ($block -notmatch "switchport trunk native vlan $($p.NativeVLAN)\s") { Add-Failure "tc-sw01.cfg: $($p.Interface) native VLAN differs from port plan ($($p.NativeVLAN))" }
    }
    elseif ($block -notmatch "switchport access vlan $($p.AccessVLAN)\s") { Add-Failure "tc-sw01.cfg: $($p.Interface) access VLAN differs from port plan ($($p.AccessVLAN))" }
    if (($p.AdminState -eq 'down') -ne ($block -match '(?m)^ shutdown\s*$')) { Add-Failure "tc-sw01.cfg: $($p.Interface) admin state differs from port plan ($($p.AdminState))" }
}

# ---------- Markdown relative links ----------
$mdFiles = Get-ChildItem -Path $Root -Recurse -File -Filter '*.md' |
    Where-Object { $_.FullName -notmatch '[\\/](node_modules|\.git)[\\/]' }
$linkPattern = '\[[^\]]*\]\(([^)\s]+)\)'
$linkCount = 0
foreach ($file in $mdFiles) {
    $content = Get-Content -Raw -Encoding UTF8 $file.FullName
    # ignore fenced code blocks
    $content = [regex]::Replace($content, '(?ms)^```.*?^```', '')
    foreach ($m in [regex]::Matches($content, $linkPattern)) {
        $target = $m.Groups[1].Value
        if ($target -match '^(https?:|mailto:|#)') { continue }
        $pathPart = ($target -split '#')[0]
        if (-not $pathPart) { continue }
        $linkCount++
        $resolved = Join-Path $file.DirectoryName ([uri]::UnescapeDataString($pathPart))
        if (-not (Test-Path $resolved)) {
            $rel = $file.FullName.Substring($Root.Length).TrimStart('\', '/')
            Add-Failure "broken link in ${rel}: $target"
        }
    }
}

# ---------- Result ----------
Write-Host ("Employees: {0} | Assets: {1} | Static IPs: {2} | VLANs: {3} | Switch ports: {4} | Markdown files: {5} | Relative links: {6}" -f `
    $employees.Count, $inventory.Count, $static.Count, $vlans.Count, $ports.Count, $mdFiles.Count, $linkCount)

if ($script:Failures.Count -gt 0) {
    $script:Failures | ForEach-Object { Write-Host "FAIL: $_" -ForegroundColor Red }
    Write-Host "$($script:Failures.Count) check(s) failed." -ForegroundColor Red
    exit 1
}
Write-Host 'All repository data checks passed.' -ForegroundColor Green
exit 0
