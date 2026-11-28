<#
.SYNOPSIS
    Morning health check of Windows servers (or any Windows PC): uptime,
    disk space, pending reboot, role services, stopped automatic services,
    System-log errors and clock offset. PASS / WARN / FAIL. Read-only.

.DESCRIPTION
    For each computer (CIM over WinRM; the local computer needs no remoting):

      Uptime            WARN above -MaxUptimeDays (35): a monthly patch reboot was missed
      Disk free space   per fixed volume, WARN < 20 %, FAIL < 10 % (Get-TcDiskStatus)
      Pending reboot    CBS RebootPending, Windows Update RebootRequired,
                        PendingFileRenameOperations - WARN
      Role services     services listed for the host in data/server-roles.csv
                        (NTDS, DNS, Netlogon ... on a DC) - FAIL if not running
      Automatic services Auto-start services that are stopped (minus a list of
                        services that stop by design) - WARN
      System log        Critical events in -EventHours (24) - FAIL; more than
                        -MaxErrors Error events - WARN
      Clock offset      only with -TimeSource: w32tm /stripchart against the
                        PDC emulator; WARN above 2 s, FAIL above 60 s (Kerberos
                        breaks at 300 s - SC-INF-001)

    Output: result rows, CSV in -OutputFolder, exit code 0/1/2 (PASS/WARN/FAIL)
    for a scheduled task or monitoring agent.

.EXAMPLE
    .\Get-TechCorpServerHealth.ps1
    Checks this computer.

.EXAMPLE
    .\Get-TechCorpServerHealth.ps1 -ComputerName TC-DC01, TC-DC02, TC-FS01 -TimeSource TC-DC01
#>
[CmdletBinding()]
param(
    [string[]]$ComputerName = @($env:COMPUTERNAME),
    [ValidateRange(1, 365)][int]$MaxUptimeDays = 35,
    [int]$DiskWarnPercent = 20,
    [int]$DiskFailPercent = 10,
    [int]$EventHours = 24,
    [int]$MaxErrors = 20,
    [string]$TimeSource,
    [string[]]$IgnoreService = @('edgeupdate', 'gupdate', 'MapsBroker', 'RemoteRegistry', 'sppsvc', 'TrustedInstaller', 'WbioSrvc', 'GoogleUpdater*', 'MicrosoftEdgeElevationService', 'CDPSvc', 'tiledatamodelsvc', 'BITS', 'wuauserv', 'UsoSvc', 'WaaSMedicSvc', 'ShellHWDetection', 'StateRepository'),
    [string]$Root,
    [string]$OutputFolder = (Join-Path (Get-Location) 'output/reports'),
    [datetime]$Now = (Get-Date)
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../modules/TechCorp.Admin/TechCorp.Admin.psd1') -Force
if (-not $Root) { $Root = Get-TcRepoRoot -StartPath $PSScriptRoot }

$roles = @{}
foreach ($r in Import-TcData server-roles -Root $Root) { $roles[$r.Hostname] = $r }
$results = New-Object System.Collections.Generic.List[object]
$HKLM = [uint32]2147483650

function Test-RegistryKey($Cim, [string]$Key) {
    $r = Invoke-CimMethod -ClassName StdRegProv -Namespace root/default -MethodName EnumKey -Arguments @{ hDefKey = $HKLM; sSubKeyName = $Key } @Cim
    return $r.ReturnValue -eq 0
}

function Test-RegistryValue($Cim, [string]$Key, [string]$Value) {
    $r = Invoke-CimMethod -ClassName StdRegProv -Namespace root/default -MethodName GetMultiStringValue -Arguments @{ hDefKey = $HKLM; sSubKeyName = $Key; sValueName = $Value } @Cim
    return $r.ReturnValue -eq 0 -and @($r.sValue).Count -gt 0
}

foreach ($computer in $ComputerName) {
    $isLocal = $computer -in $env:COMPUTERNAME, 'localhost', '.'
    $cim = @{ ErrorAction = 'Stop' }
    $session = $null
    try {
        if (-not $isLocal) { $session = New-CimSession -ComputerName $computer -OperationTimeoutSec 20 -ErrorAction Stop; $cim.CimSession = $session }
        $os = Get-CimInstance Win32_OperatingSystem @cim
    }
    catch {
        $results.Add((New-TcResult -Check 'Reachable' -Target $computer -Status FAIL -Detail $_.Exception.Message))
        if ($session) { Remove-CimSession $session }
        continue
    }

    try {
        # Uptime
        $uptime = $Now - $os.LastBootUpTime
        $status = if ($uptime.TotalDays -gt $MaxUptimeDays) { 'WARN' } else { 'PASS' }
        $results.Add((New-TcResult -Check 'Uptime' -Target $computer -Status $status -Detail ('{0:N1} days since {1:yyyy-MM-dd HH:mm}' -f $uptime.TotalDays, $os.LastBootUpTime)))

        # Disks
        $disks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' @cim)
        foreach ($d in Get-TcDiskStatus -Disk $disks -ComputerName $computer -WarnPercent $DiskWarnPercent -FailPercent $DiskFailPercent) { $results.Add($d) }

        # Pending reboot
        $reasons = @()
        if (Test-RegistryKey $cim 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $reasons += 'servicing stack' }
        if (Test-RegistryKey $cim 'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $reasons += 'Windows Update' }
        if (Test-RegistryValue $cim 'SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations') { $reasons += 'pending file renames' }
        $status = if ($reasons) { 'WARN' } else { 'PASS' }
        $detail = if ($reasons) { 'reboot pending: ' + ($reasons -join ', ') } else { 'no reboot pending' }
        $results.Add((New-TcResult -Check 'Pending reboot' -Target $computer -Status $status -Detail $detail))

        # Services
        $services = @(Get-CimInstance Win32_Service @cim)
        $byName = @{}; foreach ($s in $services) { $byName[$s.Name] = $s }
        $roleServices = @()
        $shortName = $computer.Split('.')[0].ToUpperInvariant()
        if ($roles.ContainsKey($shortName) -and $roles[$shortName].Services) { $roleServices = $roles[$shortName].Services.Split(';') }
        foreach ($name in $roleServices) {
            if (-not $byName.ContainsKey($name)) { $results.Add((New-TcResult -Check 'Role service' -Target "$computer $name" -Status FAIL -Detail 'not installed')); continue }
            $s = $byName[$name]
            $status = if ($s.State -eq 'Running') { 'PASS' } else { 'FAIL' }
            $results.Add((New-TcResult -Check 'Role service' -Target "$computer $name" -Status $status -Detail "$($s.State), start mode $($s.StartMode)"))
        }
        $stopped = @($services | Where-Object {
            $svc = $_
            $svc.StartMode -eq 'Auto' -and $svc.State -ne 'Running' -and $roleServices -notcontains $svc.Name -and
                @($IgnoreService | Where-Object { $svc.Name -like $_ }).Count -eq 0
        })
        $status = if ($stopped) { 'WARN' } else { 'PASS' }
        $detail = if ($stopped) { 'stopped: ' + (@($stopped | ForEach-Object Name) -join ', ') } else { 'all automatic services running' }
        $results.Add((New-TcResult -Check 'Automatic services' -Target $computer -Status $status -Detail $detail))

        # System log
        $filter = @{ LogName = 'System'; Level = 1, 2; StartTime = $Now.AddHours(-$EventHours) }
        $eventParams = @{ FilterHashtable = $filter; ErrorAction = 'SilentlyContinue' }
        if (-not $isLocal) { $eventParams.ComputerName = $computer }
        $events = @(Get-WinEvent @eventParams)
        $critical = @($events | Where-Object Level -eq 1)
        $errors = @($events | Where-Object Level -eq 2)
        $status = if ($critical) { 'FAIL' } elseif ($errors.Count -gt $MaxErrors) { 'WARN' } else { 'PASS' }
        $top = @($events | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', '
        $results.Add((New-TcResult -Check 'System log' -Target $computer -Status $status -Detail ("{0} critical, {1} error(s) in {2} h{3}" -f $critical.Count, $errors.Count, $EventHours, $(if ($top) { " - $top" } else { '' }))))
    }
    catch {
        $results.Add((New-TcResult -Check 'Health query' -Target $computer -Status FAIL -Detail $_.Exception.Message))
    }
    finally { if ($session) { Remove-CimSession $session } }

    # Clock offset (run from here against the time source)
    if ($TimeSource -and $computer -ne $TimeSource) {
        $lines = @(& w32tm.exe /stripchart "/computer:$computer" /samples:3 /dataonly 2>&1 | ForEach-Object { [string]$_ })
        $offset = ConvertFrom-TcStripchart -Line $lines
        if ($null -eq $offset) { $results.Add((New-TcResult -Check 'Clock offset' -Target $computer -Status WARN -Detail 'w32tm returned no samples')) }
        else {
            $abs = [math]::Abs($offset)
            $status = if ($abs -gt 60) { 'FAIL' } elseif ($abs -gt 2) { 'WARN' } else { 'PASS' }
            $results.Add((New-TcResult -Check 'Clock offset' -Target $computer -Status $status -Detail ('{0:+0.000;-0.000} s against this computer ({1})' -f $offset, $env:COMPUTERNAME)))
        }
    }
}

if (-not (Test-Path -LiteralPath $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null }
$csv = Join-Path $OutputFolder "server-health-$($Now.ToString('yyyy-MM-dd-HHmm')).csv"
$results | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
$overall = Get-TcOverallStatus -Result $results.ToArray()
Write-Host "Server health: $($ComputerName.Count) computer(s), $($results.Count) check(s), overall $overall -> $csv"
$results
exit (Get-TcExitCode -Result $results.ToArray())
