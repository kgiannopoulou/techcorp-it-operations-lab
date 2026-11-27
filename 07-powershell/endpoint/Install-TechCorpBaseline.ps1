<#
.SYNOPSIS
    Installs the TechCorp software baseline on a Windows 11 laptop for the
    person who will use it, from 04-endpoint-management/software-installation/app-catalogue.csv.

.DESCRIPTION
    Every laptop gets the core apps (Target = All). On top of that the
    laptop's owner decides what else is installed:
      Department:<Code>  - apps for a department (codes from department-map.csv)
      Tier:<DeviceTier>  - apps for a hardware tier (Standard, Developer, Creative, IT)

    The owner's department and tier are looked up in employees.csv from
    -Username, or given directly with -Department / -Tier (spares).

    Methods:
      winget      - winget install --exact --silent --scope machine
      odt         - Office Deployment Tool with m365-apps-configuration.xml
      capability  - Add-WindowsCapability (RSAT)
      feature     - WSL (wsl --install --no-distribution)
      builtin     - ships with Windows, only reported
      manual      - vendor installer / portal, only reported (listed as a to-do)

    Idempotent: anything already present is skipped. Supports -WhatIf.
    Log: C:\ProgramData\TechCorp\Logs\baseline-<date>.csv

    -SelfTest validates the catalogue offline (methods, IDs, targets, the ODT
    XML, every employee's resulting app list) and runs in CI.

.PARAMETER Username
    Laptop owner (employees.csv Username), e.g. armin.arlert.

.PARAMETER Department
    Department code (when there is no owner yet). Default: none.

.PARAMETER Tier
    Device tier (when there is no owner yet). Default: Standard.

.PARAMETER OdtPath
    Folder that contains the Office Deployment Tool setup.exe.

.PARAMETER ListOnly
    Show the apps that would be installed and exit.

.PARAMETER SelfTest
    Validate the catalogue against the company data. Exit 0 = pass, 1 = fail.

.EXAMPLE
    .\Install-TechCorpBaseline.ps1 -Username armin.arlert -ListOnly

.EXAMPLE
    .\Install-TechCorpBaseline.ps1 -Username nile.dok -OdtPath C:\Install\ODT

.EXAMPLE
    ./Install-TechCorpBaseline.ps1 -SelfTest
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Owner')]
param(
    [Parameter(ParameterSetName = 'Owner', Mandatory)]
    [string]$Username,

    [Parameter(ParameterSetName = 'Spare')]
    [string]$Department,

    [Parameter(ParameterSetName = 'Spare')]
    [ValidateSet('Standard', 'Developer', 'Creative', 'IT')]
    [string]$Tier = 'Standard',

    [Parameter(ParameterSetName = 'Owner')]
    [Parameter(ParameterSetName = 'Spare')]
    [string]$OdtPath = 'C:\ProgramData\TechCorp\ODT',

    [Parameter(ParameterSetName = 'Owner')]
    [Parameter(ParameterSetName = 'Spare')]
    [switch]$ListOnly,

    [Parameter(ParameterSetName = 'SelfTest', Mandatory)]
    [switch]$SelfTest,

    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$catalogueDir = Join-Path $Root '04-endpoint-management/software-installation'
$catalogue = @(Import-Csv -LiteralPath (Join-Path $catalogueDir 'app-catalogue.csv') -Encoding UTF8)
$employees = @(Import-Csv -LiteralPath (Join-Path $Root '00-company-overview/data/employees.csv') -Encoding UTF8)
$departments = @(Import-Csv -LiteralPath (Join-Path $Root '03-windows-server/users-and-groups/department-map.csv') -Encoding UTF8)
$odtXml = Join-Path $catalogueDir 'm365-apps-configuration.xml'

$codeByDepartment = @{}
foreach ($d in $departments) { $codeByDepartment[$d.Department] = $d.Code }
$validMethods = 'winget', 'odt', 'capability', 'feature', 'builtin', 'manual'
$validTiers = 'Standard', 'Developer', 'Creative', 'IT'

function Get-TargetApp([string]$DepartmentCode, [string]$DeviceTier) {
    return @($catalogue | Where-Object {
        $_.Target -eq 'All' -or $_.Target -eq "Department:$DepartmentCode" -or $_.Target -eq "Tier:$DeviceTier"
    })
}

# ---------------------------------------------------------------- self-test
if ($SelfTest) {
    $failures = New-Object System.Collections.Generic.List[string]
    $passed = 0
    function Assert-Catalogue([bool]$Condition, [string]$Message) {
        if ($Condition) { $script:passed++ } else { $failures.Add($Message) }
    }

    $catalogue | Group-Object App | Where-Object Count -gt 1 | ForEach-Object { $failures.Add("app-catalogue.csv: duplicate app '$($_.Name)'") }
    foreach ($a in $catalogue) {
        Assert-Catalogue ($a.Method -in $validMethods) "app-catalogue.csv: '$($a.App)' has unknown method '$($a.Method)'"
        switch ($a.Method) {
            'winget' { Assert-Catalogue ($a.Id -match '^[A-Za-z0-9][\w-]*(\.[\w+-]+)+$') "app-catalogue.csv: '$($a.App)' winget id '$($a.Id)' is not Publisher.Package" }
            'capability' { Assert-Catalogue ($a.Id -match '^Rsat\.[\w.-]+~~~~[\d.]+$') "app-catalogue.csv: '$($a.App)' capability '$($a.Id)' is not a full capability name" }
            'odt' { Assert-Catalogue (Test-Path -LiteralPath (Join-Path $catalogueDir $a.Id)) "app-catalogue.csv: '$($a.App)' ODT file '$($a.Id)' is missing" }
            'feature' { Assert-Catalogue ($a.Id -eq 'wsl') "app-catalogue.csv: '$($a.App)' - only the 'wsl' feature is supported" }
            default { Assert-Catalogue (-not $a.Id) "app-catalogue.csv: '$($a.App)' is $($a.Method) and must not have an Id" }
        }
        if ($a.Target -like 'Department:*') {
            $code = $a.Target.Substring(11)
            Assert-Catalogue ($code -in $codeByDepartment.Values) "app-catalogue.csv: '$($a.App)' targets unknown department code '$code'"
            Assert-Catalogue (@($employees | Where-Object { $codeByDepartment[$_.Department] -eq $code }).Count -gt 0) "app-catalogue.csv: '$($a.App)' targets a department with no employees"
        }
        elseif ($a.Target -like 'Tier:*') {
            $t = $a.Target.Substring(5)
            Assert-Catalogue ($t -in $validTiers) "app-catalogue.csv: '$($a.App)' targets unknown tier '$t'"
            Assert-Catalogue (@($employees | Where-Object DeviceTier -eq $t).Count -gt 0) "app-catalogue.csv: '$($a.App)' targets tier '$t' that nobody has"
        }
        else { Assert-Catalogue ($a.Target -eq 'All') "app-catalogue.csv: '$($a.App)' target '$($a.Target)' must be All, Department:<Code> or Tier:<Tier>" }
    }

    # ODT configuration
    [xml]$x = Get-Content -LiteralPath $odtXml -Raw
    $products = @($x.Configuration.Add.Product | ForEach-Object { $_.ID })
    Assert-Catalogue ('O365BusinessRetail' -in $products) 'm365-apps-configuration.xml: product must be O365BusinessRetail (Microsoft 365 Apps for business)'
    Assert-Catalogue ($x.Configuration.Add.OfficeClientEdition -eq '64') 'm365-apps-configuration.xml: 64-bit only'
    Assert-Catalogue ($x.Configuration.Add.Channel -in 'Current', 'MonthlyEnterprise') 'm365-apps-configuration.xml: channel must be Current or MonthlyEnterprise'
    Assert-Catalogue ($x.Configuration.Display.Level -eq 'None' -and $x.Configuration.Display.AcceptEULA -eq 'TRUE') 'm365-apps-configuration.xml: must be silent with EULA accepted'

    # Every employee gets a sensible set
    $core = @($catalogue | Where-Object Target -eq 'All' | ForEach-Object { $_.App })
    foreach ($e in $employees) {
        Assert-Catalogue ($e.DeviceTier -in $validTiers) "employees.csv: $($e.Username) has unknown DeviceTier '$($e.DeviceTier)'"
        $apps = @(Get-TargetApp $codeByDepartment[$e.Department] $e.DeviceTier | ForEach-Object { $_.App })
        foreach ($c in $core) { Assert-Catalogue ($c -in $apps) "baseline: $($e.Username) does not get core app '$c'" }
        if ($e.DeviceTier -eq 'Developer') {
            foreach ($need in 'Docker Desktop', 'Windows Subsystem for Linux', 'Git') { Assert-Catalogue ($need -in $apps) "baseline: developer $($e.Username) is missing $need" }
        }
        if ($e.DeviceTier -ne 'IT') { Assert-Catalogue (@($apps | Where-Object { $_ -like 'RSAT*' }).Count -eq 0) "baseline: $($e.Username) would get admin tools (RSAT)" }
    }
    $docker = @($catalogue | Where-Object App -eq 'Docker Desktop')
    Assert-Catalogue ($docker.Count -eq 1 -and $docker[0].Target -eq 'Tier:Developer') 'baseline: Docker Desktop must be Developer tier only'

    Write-Host ("App catalogue: {0} apps ({1} core) | {2} employees checked" -f $catalogue.Count, $core.Count, $employees.Count)
    if ($failures.Count -gt 0) {
        $failures | ForEach-Object { Write-Host "FAIL: $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host "All $passed app catalogue checks passed." -ForegroundColor Green
    exit 0
}

# ---------------------------------------------------------------- resolve owner
if ($PSCmdlet.ParameterSetName -eq 'Owner') {
    $owner = @($employees | Where-Object Username -eq $Username)
    if ($owner.Count -ne 1) { throw "Username '$Username' is not in employees.csv" }
    $Department = $codeByDepartment[$owner[0].Department]
    $Tier = $owner[0].DeviceTier
}
$apps = Get-TargetApp $Department $Tier
Write-Host "Baseline for department '$Department', tier '$Tier': $($apps.Count) apps"

if ($ListOnly) {
    $apps | Select-Object App, Method, Id, Target
    return
}

$identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell (as the LAPS Administrator or wadm- account).'
}

$logDir = 'C:\ProgramData\TechCorp\Logs'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir }
$log = New-Object System.Collections.Generic.List[object]
function Write-AppResult([string]$App, [string]$Result) {
    $log.Add([pscustomobject]@{ Time = (Get-Date).ToString('s'); Computer = $env:COMPUTERNAME; App = $App; Result = $Result })
    Write-Host ('{0,-34} {1}' -f $App, $Result)
}

foreach ($a in $apps) {
    switch ($a.Method) {
        'winget' {
            $null = & winget.exe list --id $a.Id --exact --accept-source-agreements --disable-interactivity 2>&1
            if ($LASTEXITCODE -eq 0) { Write-AppResult $a.App 'present'; continue }
            if ($PSCmdlet.ShouldProcess($a.Id, 'winget install')) {
                $out = & winget.exe install --id $a.Id --exact --silent --scope machine --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
                if ($LASTEXITCODE -eq 0) { Write-AppResult $a.App 'installed' } else { Write-AppResult $a.App "FAILED (winget exit $LASTEXITCODE) $(($out | Select-Object -Last 1))" }
            }
        }
        'odt' {
            $c2r = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
            if ($c2r -and $c2r.PSObject.Properties['ProductReleaseIds'] -and $c2r.ProductReleaseIds -like '*O365BusinessRetail*') { Write-AppResult $a.App 'present'; continue }
            $setup = Join-Path $OdtPath 'setup.exe'
            if (-not (Test-Path -LiteralPath $setup)) { Write-AppResult $a.App "FAILED - Office Deployment Tool not found at $setup"; continue }
            if ($PSCmdlet.ShouldProcess($a.App, 'Office Deployment Tool /configure')) {
                $p = Start-Process -FilePath $setup -ArgumentList '/configure', "`"$(Join-Path $catalogueDir $a.Id)`"" -Wait -PassThru
                Write-AppResult $a.App $(if ($p.ExitCode -eq 0) { 'installed' } else { "FAILED (ODT exit $($p.ExitCode))" })
            }
        }
        'capability' {
            $cap = Get-WindowsCapability -Online -Name $a.Id
            if ($cap.State -eq 'Installed') { Write-AppResult $a.App 'present'; continue }
            if ($PSCmdlet.ShouldProcess($a.Id, 'Add-WindowsCapability')) {
                $null = Add-WindowsCapability -Online -Name $a.Id
                Write-AppResult $a.App 'installed'
            }
        }
        'feature' {
            $null = & wsl.exe --status 2>&1
            if ($LASTEXITCODE -eq 0) { Write-AppResult $a.App 'present'; continue }
            if ($PSCmdlet.ShouldProcess('WSL', 'wsl --install --no-distribution')) {
                $null = & wsl.exe --install --no-distribution 2>&1
                Write-AppResult $a.App $(if ($LASTEXITCODE -eq 0) { 'installed (restart required)' } else { "FAILED (wsl exit $LASTEXITCODE)" })
            }
        }
        'builtin' { Write-AppResult $a.App 'built in' }
        'manual' { Write-AppResult $a.App "TODO manual - $($a.Notes)" }
    }
}

$logFile = Join-Path $logDir "baseline-$(Get-Date -Format yyyyMMdd-HHmm).csv"
$log | Export-Csv -LiteralPath $logFile -NoTypeInformation -Encoding UTF8
Write-Host "Log: $logFile"
if (@($log | Where-Object Result -like 'FAILED*').Count -gt 0) { exit 1 }
