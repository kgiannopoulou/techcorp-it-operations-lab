<#
.SYNOPSIS
    Checks that every server and network device answers on the TCP ports its
    role needs (data/server-roles.csv). PASS / FAIL per port. Read-only.

.DESCRIPTION
    "The server is up" (ping) is not "the service works". This connects to
    each port with a 1.5 s timeout (Test-TcTcpPort) - DNS 53, Kerberos 88,
    LDAP 389, SMB 445, AD Web Services 9389 on the DCs, SMB on the file
    server, the firewall GUI, printer ports.

    Addresses come from hardware-inventory.csv, so a DNS failure does not
    hide a service failure; -ByName connects by hostname instead and tests
    name resolution too (FAIL "DNS" when the name does not resolve).

    Run it from the MGMT VLAN (firewall rule MGMT 2 allows everything) - from
    STAFF some ports are blocked by design and Test-TechCorpNetwork.ps1 is the
    right tool there.

.EXAMPLE
    .\Test-TechCorpServicePort.ps1

.EXAMPLE
    .\Test-TechCorpServicePort.ps1 -ComputerName TC-DC01, TC-DC02 -ByName -OutputPath .\output\dc-ports.csv

.EXAMPLE
    ./Test-TechCorpServicePort.ps1 -Target @{ Hostname = 'localhost'; Address = '127.0.0.1'; TcpPorts = '8080' }
    Ad-hoc targets instead of the data file (used by the tests).
#>
[CmdletBinding()]
param(
    [string[]]$ComputerName,
    [switch]$ByName,
    [ValidateRange(100, 60000)][int]$TimeoutMs = 1500,
    [hashtable[]]$Target,
    [string]$Root,
    [string]$OutputPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../modules/TechCorp.Admin/TechCorp.Admin.psd1') -Force

if ($Target) {
    $targets = @($Target | ForEach-Object { [pscustomobject]@{ Hostname = $_.Hostname; Address = $_.Address; TcpPorts = [string]$_.TcpPorts; Role = 'ad-hoc' } })
}
else {
    if (-not $Root) { $Root = Get-TcRepoRoot -StartPath $PSScriptRoot }
    $ipByHost = @{}
    foreach ($a in Import-TcData inventory -Root $Root) { if ($a.Hostname -and $a.IPAddress -match '^\d+\.\d+\.\d+\.\d+$') { $ipByHost[$a.Hostname] = $a.IPAddress } }
    $targets = @(Import-TcData server-roles -Root $Root | Where-Object TcpPorts | ForEach-Object {
        [pscustomobject]@{ Hostname = $_.Hostname; Address = $(if ($ipByHost.ContainsKey($_.Hostname)) { $ipByHost[$_.Hostname] } else { '' }); TcpPorts = $_.TcpPorts; Role = $_.Role }
    })
    if ($ComputerName) { $targets = @($targets | Where-Object { $_.Hostname -in $ComputerName }) }
    if ($targets.Count -eq 0) { throw "No targets - check -ComputerName against data/server-roles.csv." }
}

$portNames = @{ 53 = 'DNS'; 88 = 'Kerberos'; 135 = 'RPC endpoint mapper'; 389 = 'LDAP'; 443 = 'HTTPS'; 445 = 'SMB'; 464 = 'Kerberos password'; 631 = 'IPP'; 3268 = 'Global catalog'; 5985 = 'WinRM'; 9100 = 'RAW print'; 9389 = 'AD Web Services' }
$results = New-Object System.Collections.Generic.List[object]
foreach ($t in $targets) {
    $connectTo = $t.Address
    if ($ByName -or -not $connectTo) {
        $connectTo = $t.Hostname
        try { [void][System.Net.Dns]::GetHostAddresses($t.Hostname) }
        catch {
            $results.Add((New-TcResult -Check 'DNS' -Target $t.Hostname -Status FAIL -Detail 'name does not resolve - ports not tested'))
            continue
        }
    }
    foreach ($p in $t.TcpPorts.Split(';')) {
        $port = [int]$p
        $label = if ($portNames.ContainsKey($port)) { $portNames[$port] } else { "TCP $port" }
        $open = Test-TcTcpPort -ComputerName $connectTo -Port $port -TimeoutMs $TimeoutMs
        $status = if ($open) { 'PASS' } else { 'FAIL' }
        $detail = if ($open) { "$connectTo`:$port open" } else { "$connectTo`:$port closed, filtered or no answer in $TimeoutMs ms" }
        $results.Add((New-TcResult -Check "Port $port $label" -Target $t.Hostname -Status $status -Detail $detail))
    }
}

if ($OutputPath) {
    $dir = Split-Path -Parent $OutputPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
}
$fail = @($results | Where-Object Status -eq 'FAIL').Count
Write-Host "Service ports: $($targets.Count) host(s), $($results.Count) check(s), $fail FAIL"
$results
exit (Get-TcExitCode -Result $results.ToArray())
