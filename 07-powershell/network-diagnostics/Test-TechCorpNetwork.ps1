<#
.SYNOPSIS
    Verifies a TechCorp client's network configuration and the inter-VLAN policy
    from the client's point of view. Prints PASS / FAIL / SKIP per test.

.DESCRIPTION
    Run it on a lab client in any VLAN. The script:
      1. Detects the VLAN profile from the client's IPv4 address (10.10.<VLAN>.x)
         or uses -VlanProfile.
      2. Checks IP configuration (not APIPA, right subnet, gateway .1).
      3. Checks gateway reachability and DNS resolution.
      4. Probes TCP ports that the firewall policy should ALLOW or BLOCK for that
         VLAN (see 02-network-infrastructure/firewall/firewall-rules.md).

    TCP results: Open (SYN-ACK), Refused (RST - the path is allowed but nothing
    listens) or Filtered (timeout - dropped by a firewall, or the host does not
    exist). Tests against hosts that are built in later phases (domain
    controllers, file server, printers) are SKIPPED unless -Include names them.

    Read-only: changes nothing on the client or the network.

.PARAMETER VlanProfile
    Mgmt, Staff, Printers or Guest. Auto-detected when omitted.

.PARAMETER Include
    Optional target groups that exist in your lab: Switch, Servers, Printers.
    (The VirtualBox lab has no physical switch; the Packet Tracer lab does.)

.PARAMETER TimeoutMs
    TCP connect timeout per probe (default 1500 ms).

.PARAMETER OutputPath
    Optional CSV path for evidence, e.g. .\output\staff-20270112.csv

.EXAMPLE
    .\Test-TechCorpNetwork.ps1
    Auto-detects the VLAN and runs the tests that apply today.

.EXAMPLE
    .\Test-TechCorpNetwork.ps1 -VlanProfile Guest -OutputPath .\output\guest.csv

.EXAMPLE
    .\Test-TechCorpNetwork.ps1 -Include Servers,Printers
    After Phase 2, when TC-DC01 / TC-FS01 exist.
#>
[CmdletBinding()]
param(
    [ValidateSet('Mgmt', 'Staff', 'Printers', 'Guest')]
    [string]$VlanProfile,

    [ValidateSet('Switch', 'Servers', 'Printers')]
    [string[]]$Include = @(),

    [ValidateRange(200, 10000)]
    [int]$TimeoutMs = 1500,

    [string]$OutputPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$vlanByOctet = @{ 10 = 'Mgmt'; 20 = 'Staff'; 40 = 'Printers'; 50 = 'Guest' }
$octetByProfile = @{ Mgmt = 10; Staff = 20; Printers = 40; Guest = 50 }

# Expected policy per source profile. Requires = target group that must exist (else SKIP).
$policy = @(
    # Name                          Host           Port  Requires   Mgmt     Staff    Printers Guest
    @{ Name = 'Switch SSH (TC-SW01)'; Host = '10.10.10.2'; Port = 22; Requires = 'Switch'; Mgmt = 'Allow'; Staff = 'Block'; Printers = 'Block'; Guest = 'Block' }
    @{ Name = 'Firewall web GUI (own gateway)'; Host = 'GATEWAY'; Port = 443; Requires = ''; Mgmt = 'Allow'; Staff = 'Block'; Printers = 'Block'; Guest = 'Block' }
    @{ Name = 'DC LDAP (TC-DC01)'; Host = '10.10.30.11'; Port = 389; Requires = 'Servers'; Mgmt = 'Allow'; Staff = 'Allow'; Printers = 'Block'; Guest = 'Block' }
    @{ Name = 'DC Kerberos (TC-DC01)'; Host = '10.10.30.11'; Port = 88; Requires = 'Servers'; Mgmt = 'Allow'; Staff = 'Allow'; Printers = 'Block'; Guest = 'Block' }
    @{ Name = 'File server SMB (TC-FS01)'; Host = '10.10.30.20'; Port = 445; Requires = 'Servers'; Mgmt = 'Allow'; Staff = 'Allow'; Printers = 'Allow'; Guest = 'Block' }
    @{ Name = 'Printer RAW 9100 (TC-PRN01)'; Host = '10.10.40.10'; Port = 9100; Requires = 'Printers'; Mgmt = 'Allow'; Staff = 'Allow'; Printers = 'Allow'; Guest = 'Block' }
    @{ Name = 'Internet HTTPS (1.1.1.1)'; Host = '1.1.1.1'; Port = 443; Requires = ''; Mgmt = 'Allow'; Staff = 'Allow'; Printers = 'Block'; Guest = 'Allow' }
    @{ Name = 'Internet SMTP submission (587)'; Host = 'smtp.office365.com'; Port = 587; Requires = ''; Mgmt = 'Allow'; Staff = 'Allow'; Printers = 'Allow'; Guest = 'Allow' }
)

$results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$Test, [string]$Expected, [string]$Observed, [string]$Status, [string]$Detail = '') {
    $results.Add([pscustomobject]@{ Test = $Test; Expected = $Expected; Observed = $Observed; Status = $Status; Detail = $Detail })
}

function Get-TcpState([string]$TargetHost, [int]$Port, [int]$Timeout) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($TargetHost, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($Timeout)) { return 'Filtered' }
        try { $client.EndConnect($async); return 'Open' }
        catch {
            $inner = $_.Exception.InnerException
            if ($inner -is [System.Net.Sockets.SocketException] -and $inner.SocketErrorCode -eq 'ConnectionRefused') { return 'Refused' }
            if ($inner -is [System.Net.Sockets.SocketException] -and $inner.SocketErrorCode -eq 'HostNotFound') { return 'NoDNS' }
            return 'Filtered'
        }
    }
    catch { return 'Error' }
    finally { $client.Close() }
}

# ---------- 1. Local IP configuration ----------
$nic = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
    Where-Object { $_.OperationalStatus -eq 'Up' -and $_.NetworkInterfaceType -ne 'Loopback' } |
    ForEach-Object {
        $props = $_.GetIPProperties()
        foreach ($ua in $props.UnicastAddresses) {
            if ($ua.Address.AddressFamily -eq 'InterNetwork') {
                [pscustomobject]@{
                    Name    = $_.Name
                    Address = $ua.Address.ToString()
                    Prefix  = $ua.PrefixLength
                    Gateway = @($props.GatewayAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' } | ForEach-Object { $_.Address.ToString() }) -join ','
                    Dns     = @($props.DnsAddresses | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | ForEach-Object { $_.ToString() }) -join ','
                }
            }
        }
    } | Sort-Object @{ Expression = { $_.Address -like '10.10.*' }; Descending = $true }, @{ Expression = { [bool]$_.Gateway }; Descending = $true } |
    Select-Object -First 1

if (-not $nic) { Write-Error 'No active IPv4 interface found.' }

$octets = $nic.Address.Split('.')
if (-not $VlanProfile) {
    if ($octets[0] -eq '10' -and $octets[1] -eq '10' -and $vlanByOctet.ContainsKey([int]$octets[2])) {
        $VlanProfile = $vlanByOctet[[int]$octets[2]]
    }
    else {
        Write-Error "Address $($nic.Address) is not in a TechCorp client VLAN (10.10.10/20/40/50.x). Use -VlanProfile to force a profile."
    }
}
$expectedNet = "10.10.$($octetByProfile[$VlanProfile])"
$gateway = "$expectedNet.1"

Write-Host "TechCorp network test - profile $VlanProfile - interface '$($nic.Name)' $($nic.Address)/$($nic.Prefix) gw $($nic.Gateway) dns $($nic.Dns)" -ForegroundColor Cyan

if ($nic.Address -like '169.254.*') {
    Add-Result 'IP address assigned by DHCP' 'Not APIPA' $nic.Address 'FAIL' 'No DHCP lease - check port VLAN, trunk and DHCP scope'
}
else {
    $inSubnet = $nic.Address -like "$expectedNet.*"
    Add-Result 'IP address in VLAN subnet' "$expectedNet.0/24" $nic.Address $(if ($inSubnet) { 'PASS' } else { 'FAIL' })
}
Add-Result 'Prefix length' '24' "$($nic.Prefix)" $(if ($nic.Prefix -eq 24) { 'PASS' } else { 'FAIL' })
Add-Result 'Default gateway' $gateway $nic.Gateway $(if ($nic.Gateway -split ',' -contains $gateway) { 'PASS' } else { 'FAIL' })

# ---------- 2. Gateway and DNS ----------
if ($VlanProfile -ne 'Guest') {
    $ping = New-Object System.Net.NetworkInformation.Ping
    try { $reply = $ping.Send($gateway, 1000).Status.ToString() } catch { $reply = 'Error' }
    Add-Result 'Ping gateway' 'Success' $reply $(if ($reply -eq 'Success') { 'PASS' } else { 'FAIL' })
}
else {
    Add-Result 'Ping gateway' 'Blocked for guests' '-' 'SKIP' 'Guest rules block all traffic to the firewall except DNS'
}

function Test-Resolve([string]$Name) {
    try { return @([System.Net.Dns]::GetHostAddresses($Name) | Where-Object AddressFamily -eq 'InterNetwork' | ForEach-Object { $_.ToString() }) -join ',' }
    catch { return '' }
}
$public = Test-Resolve 'www.microsoft.com'
Add-Result 'DNS resolves public name' 'any IPv4' $(if ($public) { $public } else { 'no answer' }) $(if ($public) { 'PASS' } else { 'FAIL' })

if ($VlanProfile -ne 'Guest') {
    $internal = Test-Resolve 'tc-sw01.corp.techcorp.example'
    Add-Result 'DNS resolves internal name (tc-sw01)' '10.10.10.2' $(if ($internal) { $internal } else { 'no answer' }) $(if ($internal -eq '10.10.10.2') { 'PASS' } else { 'FAIL' }) 'Host override on TC-FW01 DNS Resolver'
}

# ---------- 3. Policy probes ----------
foreach ($p in $policy) {
    $target = if ($p.Host -eq 'GATEWAY') { $gateway } else { $p.Host }
    $expected = $p[$VlanProfile]
    if ($p.Requires -in 'Switch', 'Servers', 'Printers' -and $p.Requires -notin $Include) {
        Add-Result $p.Name $expected '-' 'SKIP' "Target not built yet - add -Include $($p.Requires) once it exists"
        continue
    }
    $state = Get-TcpState $target $p.Port $TimeoutMs
    $reachable = $state -in 'Open', 'Refused'
    $pass = ($expected -eq 'Allow' -and $reachable) -or ($expected -eq 'Block' -and $state -eq 'Filtered')
    $detail = switch ($state) {
        'Refused' { 'Path allowed, but nothing listens on the port' }
        'Filtered' { 'No answer - firewall drop or host absent' }
        'NoDNS' { 'Name did not resolve' }
        default { '' }
    }
    Add-Result "$($p.Name) ${target}:$($p.Port)" $expected $state $(if ($pass) { 'PASS' } else { 'FAIL' }) $detail
}

# ---------- Output ----------
$results | Format-Table -AutoSize -Wrap | Out-String -Width 200 | Write-Host
$fail = @($results | Where-Object Status -eq 'FAIL').Count
$pass = @($results | Where-Object Status -eq 'PASS').Count
$skip = @($results | Where-Object Status -eq 'SKIP').Count
Write-Host ("Summary: {0} PASS, {1} FAIL, {2} SKIP" -f $pass, $fail, $skip) -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })

if ($OutputPath) {
    $dir = Split-Path -Parent $OutputPath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $results | Select-Object @{ n = 'Timestamp'; e = { (Get-Date).ToString('s') } }, @{ n = 'Computer'; e = { [Environment]::MachineName } }, @{ n = 'Profile'; e = { $VlanProfile } }, * |
        Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "Results written to $OutputPath"
}

if ($fail) { exit 1 } else { exit 0 }
