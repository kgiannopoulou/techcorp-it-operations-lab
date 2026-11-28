<#
.SYNOPSIS
    Onboards one or more new starters: logon name, Active Directory account,
    department and licence groups, manager, laptop - from an HR request.

.DESCRIPTION
    Joiner procedure (user-accounts.md section 4, BR-10) as one script.

    For every new starter it:
      1. validates the request against the repository data - department in
         department-map.csv, manager in employees.csv / AD, work model and
         device tier allowed values;
      2. generates a unique firstname.lastname logon name (ASCII, max 20
         characters, numbered on a collision with employees.csv or AD);
      3. picks the next free employee ID and, unless -AssetTag is given, the
         first Spare laptop in hardware-inventory.csv;
      4. works out the OU and groups from the CSVs: the department's role
         group plus every group whose Members column is @employees
         (LIC_M365_BusinessPremium) - the same rules as Deploy-TechCorpAd.ps1;
      5. unless -PlanOnly: creates the AD account with a random one-time
         password ("must change at next logon"), adds the groups and the
         manager. A start date in the future creates the account DISABLED -
         enable it on day 1 (the output says how);
      6. writes an onboarding record (CSV, no password) and prints the
         employees.csv row to commit, so the repository stays the source of truth.

    The one-time password is shown once on the console, for the IT
    specialist to hand over in person on day 1. It is never written to the
    record, the log or the pipeline.

    -PlanOnly needs no domain (runs in CI and on any PC) and changes nothing.
    Every change supports -WhatIf / -Confirm.

.PARAMETER Path
    CSV with one row per starter: FirstName, LastName, Department, JobTitle,
    Manager, StartDate (yyyy-MM-dd) and optionally WorkModel, DeviceTier, AssetTag.
    See new-starters.example.csv.

.PARAMETER PlanOnly
    Validate and build the plan from the repository CSVs only - no AD lookups or changes.

.PARAMETER OutputPath
    Onboarding record CSV (default .\output\onboarding-<date>.csv).

.PARAMETER LogPath
    Log file (default .\output\logs\New-TechCorpUser.log).

.EXAMPLE
    ./New-TechCorpUser.ps1 -Path ./new-starters.example.csv -PlanOnly

.EXAMPLE
    .\New-TechCorpUser.ps1 -FirstName Floch -LastName Forster -Department 'Sales & Marketing' `
        -JobTitle 'Account Executive' -Manager jean.kirstein -StartDate 2027-03-01 -WhatIf

.NOTES
    Runs on TC-DC01 or an admin PC with RSAT (ActiveDirectory module) as an
    account with the delegated "create users" right (adm-<name>).
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Single')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Csv')]
    [string]$Path,

    [Parameter(Mandatory, ParameterSetName = 'Single')][string]$FirstName,
    [Parameter(Mandatory, ParameterSetName = 'Single')][string]$LastName,
    [Parameter(Mandatory, ParameterSetName = 'Single')][string]$Department,
    [Parameter(Mandatory, ParameterSetName = 'Single')][string]$JobTitle,
    [Parameter(Mandatory, ParameterSetName = 'Single')][string]$Manager,
    [Parameter(Mandatory, ParameterSetName = 'Single')][datetime]$StartDate,
    [Parameter(ParameterSetName = 'Single')][ValidateSet('Office', 'Hybrid', 'Remote')][string]$WorkModel = 'Office',
    [Parameter(ParameterSetName = 'Single')][ValidateSet('Standard', 'Creative', 'Developer', 'IT')][string]$DeviceTier = 'Standard',
    [Parameter(ParameterSetName = 'Single')][string]$AssetTag,

    [switch]$PlanOnly,
    [string]$Server,
    [string]$DomainDn = 'DC=corp,DC=techcorp,DC=example',
    [string]$UpnSuffix = 'techcorp.example',
    [string]$Root,
    [string]$OutputPath = (Join-Path (Get-Location) "output/onboarding-$(Get-Date -Format yyyy-MM-dd).csv"),
    [string]$LogPath = (Join-Path (Get-Location) 'output/logs/New-TechCorpUser.log'),
    [datetime]$Now = (Get-Date)
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../modules/TechCorp.Admin/TechCorp.Admin.psd1') -Force
if (-not $Root) { $Root = Get-TcRepoRoot -StartPath $PSScriptRoot }

function Add-OnboardingLog([string]$Message, [string]$Level = 'INFO', [string]$File) { Write-TcLog -Message $Message -Level $Level -Path $File | Out-Null }

# ------------------------------------------------------------------ input
if ($PSCmdlet.ParameterSetName -eq 'Csv') {
    if (-not (Test-Path -LiteralPath $Path)) { throw "New-starter file not found: $Path" }
    $requests = @(Import-Csv -LiteralPath $Path -Encoding UTF8)
}
else {
    $requests = @([pscustomobject]@{
        FirstName = $FirstName; LastName = $LastName; Department = $Department; JobTitle = $JobTitle
        Manager = $Manager; StartDate = $StartDate.ToString('yyyy-MM-dd'); WorkModel = $WorkModel
        DeviceTier = $DeviceTier; AssetTag = $AssetTag
    })
}
if ($requests.Count -eq 0) { throw 'No new starters in the input.' }

$employees   = @(Import-TcData employees -Root $Root)
$inventory   = @(Import-TcData inventory -Root $Root)
$departments = @(Import-TcData departments -Root $Root)
$groupRows   = @(Import-TcData groups -Root $Root)

$deptByName = @{}; foreach ($d in $departments) { $deptByName[$d.Department] = $d }
$everyoneGroups = @($groupRows | Where-Object Members -eq '@employees' | ForEach-Object Name)

# ------------------------------------------------------------------ AD connection
$adParams = @{}
if ($Server) { $adParams.Server = $Server }
if (-not $PlanOnly) {
    if (-not (Get-Command Get-ADUser -ErrorAction SilentlyContinue)) { Import-Module ActiveDirectory -ErrorAction Stop }
}

$takenNames = New-Object System.Collections.Generic.List[string]
$employees | ForEach-Object { $takenNames.Add($_.Username) }
$usedAssets = @{}; $employees | ForEach-Object { if ($_.AssetTag) { $usedAssets[$_.AssetTag] = $true } }
$nextId = 1 + [int](@($employees | ForEach-Object { [int]($_.EmployeeID -replace '\D', '') }) | Measure-Object -Maximum).Maximum

function Get-OptionalValue($Row, [string]$Name, [string]$Default) {
    if ($Row.PSObject.Properties[$Name] -and [string]$Row.$Name) { return [string]$Row.$Name }
    return $Default
}

# ------------------------------------------------------------------ plan
$plans = New-Object System.Collections.Generic.List[object]
$errors = New-Object System.Collections.Generic.List[string]
foreach ($r in $requests) {
    $who = "$($r.FirstName) $($r.LastName)"
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($field in 'FirstName', 'LastName', 'Department', 'JobTitle', 'Manager', 'StartDate') {
        if (-not $r.PSObject.Properties[$field] -or -not ([string]$r.$field).Trim()) { $problems.Add("$field is empty") }
    }
    if ($problems.Count -gt 0) { $errors.Add("${who}: $($problems -join '; ')"); continue }

    $dept = $deptByName[$r.Department]
    if (-not $dept) { $problems.Add("unknown department '$($r.Department)' (department-map.csv: $(@($departments.Department) -join ', '))") }
    $workModel = Get-OptionalValue $r 'WorkModel' 'Office'
    $tier = Get-OptionalValue $r 'DeviceTier' 'Standard'
    if ($workModel -notin 'Office', 'Hybrid', 'Remote') { $problems.Add("WorkModel '$workModel' must be Office, Hybrid or Remote") }
    if ($tier -notin 'Standard', 'Creative', 'Developer', 'IT') { $problems.Add("DeviceTier '$tier' must be Standard, Creative, Developer or IT") }
    $start = $null
    try { $start = ConvertTo-TcDate $r.StartDate } catch { $problems.Add("StartDate '$($r.StartDate)' is not a date") }

    $managerKnown = @($employees | Where-Object Username -eq $r.Manager).Count -gt 0
    if (-not $managerKnown -and -not $PlanOnly) {
        $managerKnown = [bool](Get-ADUser -Filter "SamAccountName -eq '$($r.Manager)'" @adParams)
    }
    if (-not $managerKnown) { $problems.Add("manager '$($r.Manager)' not found") }
    if ($problems.Count -gt 0) { $errors.Add("${who}: $($problems -join '; ')"); continue }

    if (-not $PlanOnly) {
        # live accounts with the same base name (left staff, test accounts) count as taken too
        $base = (ConvertTo-TcAsciiName $r.FirstName) + '.' + (ConvertTo-TcAsciiName $r.LastName)
        $prefix = $base.Substring(0, [math]::Min(18, $base.Length))
        Get-ADUser -Filter "SamAccountName -like '$prefix*'" @adParams | ForEach-Object { $takenNames.Add($_.SamAccountName) }
    }
    $username = Get-TcUsername -FirstName $r.FirstName -LastName $r.LastName -Existing $takenNames
    $takenNames.Add($username)

    $asset = Get-OptionalValue $r 'AssetTag' ''
    $assetNote = ''
    if ($asset) {
        $row = @($inventory | Where-Object AssetTag -eq $asset)
        if ($row.Count -eq 0) { $errors.Add("${who}: asset '$asset' is not in hardware-inventory.csv"); continue }
        if ($usedAssets.ContainsKey($asset)) { $errors.Add("${who}: asset '$asset' is already assigned"); continue }
    }
    else {
        $spare = @($inventory | Where-Object { $_.Category -eq 'Laptop' -and $_.AssignedTo -eq 'Spare' -and -not $usedAssets.ContainsKey($_.AssetTag) })
        if ($tier -in 'Developer', 'IT') {
            $performance = @($spare | Where-Object Model -like '*performance*')
            if ($performance.Count -gt 0) { $spare = $performance } else { $assetNote = 'no spare performance laptop - standard spare issued, order one' }
        }
        if ($spare.Count -gt 0) { $asset = $spare[0].AssetTag }
        else { $assetNote = 'no spare laptop - order one (equipment-list.md)' }
    }
    if ($asset) { $usedAssets[$asset] = $true }

    $employeeId = 'E{0:D3}' -f $nextId; $nextId++
    $groups = @(@($dept.RoleGroup) + $everyoneGroups | Select-Object -Unique)
    $enableNow = $start.Date -le $Now.Date
    $plans.Add([pscustomobject]@{
        EmployeeID        = $employeeId
        SamAccountName    = $username
        DisplayName       = "$($r.FirstName.Trim()) $($r.LastName.Trim())"
        GivenName         = $r.FirstName.Trim()
        Surname           = $r.LastName.Trim()
        UserPrincipalName = "$username@$UpnSuffix"
        Department        = $r.Department
        Title             = $r.JobTitle.Trim()
        Manager           = $r.Manager
        StartDate         = $start.ToString('yyyy-MM-dd')
        WorkModel         = $workModel
        DeviceTier        = $tier
        AssetTag          = $asset
        OuPath            = $dept.UserOU
        OuDn              = ConvertTo-TcOuDn -Path $dept.UserOU -DomainDn $DomainDn
        Groups            = ($groups -join ';')
        EnabledAtCreation = $enableNow
        Notes             = $assetNote
        Result            = $(if ($PlanOnly) { 'Planned' } else { 'Pending' })
        EmployeesCsvRow   = (@($employeeId, $r.FirstName.Trim(), $r.LastName.Trim(), $username, $r.Department, $r.JobTitle.Trim(), $r.Manager, $workModel, $tier, $asset) |
            ForEach-Object { if ($_ -match '[,"]') { '"' + ($_ -replace '"', '""') + '"' } else { $_ } }) -join ','
    })
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Add-OnboardingLog $_ 'ERROR' $LogPath; Write-Warning $_ }
    if ($plans.Count -eq 0) { throw "No valid new starters ($($errors.Count) rejected) - nothing done." }
}

# ------------------------------------------------------------------ apply
if (-not $PlanOnly) {
    foreach ($p in $plans) {
        if (Get-ADUser -Filter "SamAccountName -eq '$($p.SamAccountName)'" @adParams) {
            $p.Result = 'Skipped - account exists'; Add-OnboardingLog "$($p.SamAccountName) exists - skipped" 'WARN' $LogPath; continue
        }
        if (-not $PSCmdlet.ShouldProcess("$($p.SamAccountName) in $($p.OuPath)", 'Create AD user')) { $p.Result = 'WhatIf'; continue }

        $password = Get-TcRandomPassword -Length 16
        $managerDn = (Get-ADUser -Identity $p.Manager @adParams).DistinguishedName
        $newUser = @{
            Name = $p.DisplayName; SamAccountName = $p.SamAccountName; UserPrincipalName = $p.UserPrincipalName
            GivenName = $p.GivenName; Surname = $p.Surname; DisplayName = $p.DisplayName; EmailAddress = $p.UserPrincipalName
            EmployeeID = $p.EmployeeID; Department = $p.Department; Title = $p.Title; Company = 'TechCorp'
            Manager = $managerDn; Path = $p.OuDn; AccountPassword = $password
            ChangePasswordAtLogon = $true; Enabled = $p.EnabledAtCreation
        }
        New-ADUser @newUser @adParams
        Add-OnboardingLog "created $($p.SamAccountName) in $($p.OuPath) (enabled=$($p.EnabledAtCreation))" 'CHANGE' $LogPath
        foreach ($g in $p.Groups.Split(';')) {
            Add-ADGroupMember -Identity $g -Members $p.SamAccountName @adParams
            Add-OnboardingLog "added $($p.SamAccountName) to $g" 'CHANGE' $LogPath
        }
        $p.Result = 'Created'

        $plain = (New-Object System.Net.NetworkCredential('', $password)).Password
        Write-Host ''
        Write-Host "  $($p.DisplayName) ($($p.SamAccountName))  one-time password: $plain" -ForegroundColor Yellow
        Write-Host '  Hand over in person on day 1 - it is not stored anywhere.' -ForegroundColor Yellow
        if (-not $p.EnabledAtCreation) { Write-Host "  Account is DISABLED until $($p.StartDate): Enable-ADAccount $($p.SamAccountName)" -ForegroundColor Yellow }
        $plain = $null; $password.Dispose()
    }
}

# ------------------------------------------------------------------ record
$dir = Split-Path -Parent $OutputPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -WhatIf:$false | Out-Null }
$plans | Select-Object * -ExcludeProperty EmployeesCsvRow, OuDn |
    Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8 -WhatIf:$false
Add-OnboardingLog "$($plans.Count) starter(s) processed, $($errors.Count) rejected, record $OutputPath" 'INFO' $LogPath

Write-Host ''
Write-Host 'Add to 00-company-overview/data/employees.csv (and set AssignedTo in hardware-inventory.csv), then commit:' -ForegroundColor Cyan
$plans | ForEach-Object { Write-Host "  $($_.EmployeesCsvRow)" }
Write-Host 'Cloud side (licence, mailbox, Teams) follows from the groups after the next Entra Connect sync - licensing-and-lifecycle.md section 2.' -ForegroundColor Cyan

$plans
if ($errors.Count -gt 0) { exit 1 }
exit 0
