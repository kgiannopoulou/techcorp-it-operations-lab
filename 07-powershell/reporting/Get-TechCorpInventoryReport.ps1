<#
.SYNOPSIS
    Hardware inventory report: counts, warranty, spare stock and assignment
    problems from hardware-inventory.csv - plus, with -Live, what the
    computers themselves report (model, serial, OS build, RAM, disk).

.DESCRIPTION
    Offline (default) it cross-checks the two source-of-truth files:
      - assets assigned to a user who is not in employees.csv (a leaver's
        laptop that was never collected)
      - employees whose AssetTag is missing or assigned to someone else
      - warranty end per asset (in-service date + WarrantyYears) - expired
        and expiring within -WarnDays
      - spare laptops below -MinSpareLaptops (a new starter would have no laptop)

    -Live queries each computer over CIM/WinRM (Win32_ComputerSystem, BIOS,
    OperatingSystem, LogicalDisk) and reports what it found next to the
    inventory row - the serial number and OS build are the facts the
    inventory cannot know before the hardware arrives. Unreachable computers
    are reported, not fatal. Without -ComputerName, -Live checks this computer.

    Writes CSV + HTML to -OutputFolder. Read-only.
    Exit code 0 = no problems, 1 = warnings (warranty, spares), 2 = assignment errors.

.EXAMPLE
    ./Get-TechCorpInventoryReport.ps1 -Now 2029-12-01

.EXAMPLE
    .\Get-TechCorpInventoryReport.ps1 -Live -ComputerName TC-LT-001, TC-LT-002, TC-FS01
#>
[CmdletBinding()]
param(
    [datetime]$InServiceDate = '2027-02-15',
    [int]$WarnDays = 90,
    [int]$MinSpareLaptops = 2,
    [switch]$Live,
    [string[]]$ComputerName,
    [string]$Root,
    [string]$OutputFolder = (Join-Path (Get-Location) 'output/reports'),
    [datetime]$Now = (Get-Date)
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../modules/TechCorp.Admin/TechCorp.Admin.psd1') -Force
if (-not $Root) { $Root = Get-TcRepoRoot -StartPath $PSScriptRoot }

$inventory = @(Import-TcData inventory -Root $Root)
$employees = @(Import-TcData employees -Root $Root)
$employeeNames = @{}; foreach ($e in $employees) { $employeeNames[$e.Username] = $e }
$assetByTag = @{}; foreach ($a in $inventory) { $assetByTag[$a.AssetTag] = $a }
$results = New-Object System.Collections.Generic.List[object]

# ------------------------------------------------------------------ summary
$summary = @($inventory | Group-Object Category | Sort-Object Name | ForEach-Object {
    $items = @($_.Group)
    [pscustomobject]@{
        Category = $_.Name
        Total    = $items.Count
        Personal = @($items | Where-Object { $employeeNames.ContainsKey($_.AssignedTo) }).Count
        Spare    = @($items | Where-Object AssignedTo -eq 'Spare').Count
        Statuses = (@($items | Group-Object Status | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ')
    }
})

# ------------------------------------------------------------------ assignments
$personalCategories = 'Laptop', 'Headset'
foreach ($a in $inventory | Where-Object { $_.Category -in $personalCategories }) {
    $owner = $a.AssignedTo
    if ($owner -eq 'Spare' -or $owner -eq 'Shared' -or $owner -eq 'IT' -or -not $owner) { continue }
    if (-not $employeeNames.ContainsKey($owner)) {
        $results.Add((New-TcResult -Check 'Assigned to a leaver / unknown user' -Target $a.AssetTag -Status FAIL -Detail "AssignedTo '$owner' is not in employees.csv - collect the device"))
    }
}
foreach ($e in $employees) {
    if (-not $e.AssetTag) { $results.Add((New-TcResult -Check 'Employee without laptop' -Target $e.Username -Status FAIL -Detail 'AssetTag empty in employees.csv')); continue }
    if (-not $assetByTag.ContainsKey($e.AssetTag)) { $results.Add((New-TcResult -Check 'Employee laptop missing' -Target $e.Username -Status FAIL -Detail "$($e.AssetTag) not in hardware-inventory.csv")); continue }
    $owner = $assetByTag[$e.AssetTag].AssignedTo
    if ($owner -ne $e.Username) { $results.Add((New-TcResult -Check 'Laptop assignment mismatch' -Target $e.Username -Status FAIL -Detail "$($e.AssetTag) is assigned to '$owner'")) }
}

# ------------------------------------------------------------------ spares
$spareLaptops = @($inventory | Where-Object { $_.Category -eq 'Laptop' -and $_.AssignedTo -eq 'Spare' })
$spareStatus = if ($spareLaptops.Count -ge $MinSpareLaptops) { 'PASS' } else { 'WARN' }
$results.Add((New-TcResult -Check 'Spare laptops' -Target 'IT store' -Status $spareStatus -Detail "$($spareLaptops.Count) spare (minimum $MinSpareLaptops): $(@($spareLaptops.AssetTag) -join ', ')"))

# ------------------------------------------------------------------ warranty
$warranty = @(Get-TcWarrantyStatus -Asset $inventory -InServiceDate $InServiceDate -WarnDays $WarnDays -Now $Now)
foreach ($w in $warranty | Where-Object { $_.Warranty -in 'Expired', 'ExpiringSoon' }) {
    $results.Add((New-TcResult -Check 'Warranty' -Target $w.AssetTag -Status WARN -Detail "$($w.Warranty) - ends $($w.WarrantyEnd.ToString('yyyy-MM-dd')) ($($w.DaysLeft) days)"))
}
$warrantyAttention = @($warranty | Where-Object { $_.Warranty -in 'Expired', 'ExpiringSoon' })

# ------------------------------------------------------------------ live
$liveRows = @()
if ($Live) {
    if (-not $ComputerName) { $ComputerName = @($env:COMPUTERNAME) }
    $liveRows = @(foreach ($c in $ComputerName) {
        $isLocal = $c -in $env:COMPUTERNAME, 'localhost', '.'
        $cim = @{ ErrorAction = 'Stop' }
        $session = $null
        try {
            if (-not $isLocal) { $session = New-CimSession -ComputerName $c -OperationTimeoutSec 15 -ErrorAction Stop; $cim.CimSession = $session }
            $cs = Get-CimInstance Win32_ComputerSystem @cim
            $bios = Get-CimInstance Win32_BIOS @cim
            $os = Get-CimInstance Win32_OperatingSystem @cim
            $sys = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($os.SystemDrive)'" @cim
            $inInventory = $assetByTag.ContainsKey($cs.Name) -or @($inventory | Where-Object Hostname -eq $cs.Name).Count -gt 0
            if (-not $inInventory) { $results.Add((New-TcResult -Check 'Live computer not in inventory' -Target $cs.Name -Status WARN -Detail 'add it to hardware-inventory.csv or rename it (naming-conventions.md)')) }
            [pscustomobject]@{
                ComputerName = $cs.Name
                InInventory  = $inInventory
                Manufacturer = $cs.Manufacturer
                Model        = $cs.Model
                SerialNumber = $bios.SerialNumber
                OS           = $os.Caption
                Build        = $os.BuildNumber
                RamGB        = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
                SystemDiskGB = [math]::Round($sys.Size / 1GB, 0)
                FreeGB       = [math]::Round($sys.FreeSpace / 1GB, 1)
                LastBoot     = $os.LastBootUpTime
                Reachable    = $true
            }
        }
        catch {
            $results.Add((New-TcResult -Check 'Live query' -Target $c -Status WARN -Detail "unreachable: $($_.Exception.Message)"))
            [pscustomobject]@{ ComputerName = $c; InInventory = $assetByTag.ContainsKey($c); Manufacturer = ''; Model = ''; SerialNumber = ''; OS = ''; Build = ''; RamGB = $null; SystemDiskGB = $null; FreeGB = $null; LastBoot = $null; Reachable = $false }
        }
        finally { if ($session) { Remove-CimSession $session } }
    })
}

# ------------------------------------------------------------------ output
if (-not (Test-Path -LiteralPath $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null }
$stamp = $Now.ToString('yyyy-MM-dd')
$warranty | Export-Csv -LiteralPath (Join-Path $OutputFolder "inventory-warranty-$stamp.csv") -NoTypeInformation -Encoding UTF8
$results | Export-Csv -LiteralPath (Join-Path $OutputFolder "inventory-checks-$stamp.csv") -NoTypeInformation -Encoding UTF8
if ($Live) { $liveRows | Export-Csv -LiteralPath (Join-Path $OutputFolder "inventory-live-$stamp.csv") -NoTypeInformation -Encoding UTF8 }
$sections = [ordered]@{
    'Checks'                    = $results.ToArray()
    'Assets by category'        = $summary
    'Warranty needing attention' = $warrantyAttention
}
if ($Live) { $sections['Live data'] = $liveRows }
$html = Join-Path $OutputFolder "inventory-$stamp.html"
ConvertTo-TcHtmlReport -Title "Hardware inventory $stamp" -Section $sections -Now $Now | Set-Content -LiteralPath $html -Encoding UTF8

Write-Host ("Inventory: {0} assets, {1} check(s): {2} FAIL, {3} WARN -> {4}" -f $inventory.Count, $results.Count,
    @($results | Where-Object Status -eq 'FAIL').Count, @($results | Where-Object Status -eq 'WARN').Count, $html)
$results
exit (Get-TcExitCode -Result $results.ToArray())
