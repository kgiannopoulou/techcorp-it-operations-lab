<#
.SYNOPSIS
    IPv4 subnet calculator: network, broadcast, mask, wildcard, host range and host count.

.DESCRIPTION
    Accepts an address in CIDR notation (10.10.20.37/24) or an address plus a
    prefix length. Returns an object, so the output can be piped, filtered or
    exported (Export-Csv). Use -SelfTest to run the built-in test cases (used by CI).

    Works on Windows PowerShell 5.1 and PowerShell 7+. No modules required.

.PARAMETER Cidr
    One or more addresses in CIDR notation, e.g. 10.10.20.37/24.

.PARAMETER SelfTest
    Runs the built-in test cases and exits with code 0 (pass) or 1 (fail).

.EXAMPLE
    ./Get-SubnetInfo.ps1 10.10.20.37/24

.EXAMPLE
    '10.10.10.0/24','10.10.50.0/26' | ./Get-SubnetInfo.ps1 | Format-Table

.EXAMPLE
    ./Get-SubnetInfo.ps1 -SelfTest
#>
[CmdletBinding(DefaultParameterSetName = 'Calc')]
param(
    [Parameter(ParameterSetName = 'Calc', Mandatory, Position = 0, ValueFromPipeline)]
    [string[]]$Cidr,

    [Parameter(ParameterSetName = 'Test')]
    [switch]$SelfTest
)

begin {
    function ConvertTo-UInt32 ([string]$Ip) {
        $parsed = $null
        if (-not [System.Net.IPAddress]::TryParse($Ip, [ref]$parsed) -or $parsed.AddressFamily -ne 'InterNetwork' -or $Ip.Split('.').Count -ne 4) {
            throw "Invalid IPv4 address: '$Ip'"
        }
        $b = $parsed.GetAddressBytes()
        return ([uint32]$b[0] -shl 24) -bor ([uint32]$b[1] -shl 16) -bor ([uint32]$b[2] -shl 8) -bor [uint32]$b[3]
    }

    function ConvertTo-DottedQuad ([uint32]$Value) {
        return '{0}.{1}.{2}.{3}' -f (($Value -shr 24) -band 255), (($Value -shr 16) -band 255), (($Value -shr 8) -band 255), ($Value -band 255)
    }

    function Get-Subnet ([string]$Text) {
        if ($Text -notmatch '^\s*(\d{1,3}(?:\.\d{1,3}){3})\s*/\s*(\d{1,2})\s*$') { throw "Use CIDR notation, e.g. 10.10.20.0/24 (got '$Text')" }
        $ip = ConvertTo-UInt32 $Matches[1]
        $len = [int]$Matches[2]
        if ($len -lt 0 -or $len -gt 32) { throw "Prefix length must be 0-32 (got $len)" }

        $all = [uint64]4294967295   # 0xFFFFFFFF (a hex literal would be parsed as Int32 -1)
        $mask = if ($len -eq 0) { [uint32]0 } else { [uint32](($all -shl (32 - $len)) -band $all) }
        $wild = [uint32]($all -bxor [uint64]$mask)
        $net = [uint32]($ip -band $mask)
        $bcast = [uint32]($net -bor $wild)
        $total = [uint64]1 -shl (32 - $len)

        switch ($len) {
            32 { $first = $net; $last = $net; $usable = 1 }
            31 { $first = $net; $last = $bcast; $usable = 2 }   # RFC 3021 point-to-point
            default { $first = [uint32]($net + 1); $last = [uint32]($bcast - 1); $usable = $total - 2 }
        }

        $o1 = ($net -shr 24) -band 255
        $o2 = ($net -shr 16) -band 255
        $private = ($o1 -eq 10) -or ($o1 -eq 172 -and $o2 -ge 16 -and $o2 -le 31) -or ($o1 -eq 192 -and $o2 -eq 168)

        [pscustomobject]@{
            Input        = $Text.Trim()
            Network      = '{0}/{1}' -f (ConvertTo-DottedQuad $net), $len
            SubnetMask   = ConvertTo-DottedQuad $mask
            Wildcard     = ConvertTo-DottedQuad $wild
            FirstHost    = ConvertTo-DottedQuad $first
            LastHost     = ConvertTo-DottedQuad $last
            Broadcast    = if ($len -ge 31) { '-' } else { ConvertTo-DottedQuad $bcast }
            TotalAddrs   = $total
            UsableHosts  = $usable
            IsPrivate    = $private
        }
    }

    if ($SelfTest) {
        $cases = @(
            @{ In = '10.10.20.37/24'; Network = '10.10.20.0/24'; Mask = '255.255.255.0'; First = '10.10.20.1'; Last = '10.10.20.254'; Bcast = '10.10.20.255'; Hosts = 254 }
            @{ In = '10.10.50.200/26'; Network = '10.10.50.192/26'; Mask = '255.255.255.192'; First = '10.10.50.193'; Last = '10.10.50.254'; Bcast = '10.10.50.255'; Hosts = 62 }
            @{ In = '172.20.5.130/25'; Network = '172.20.5.128/25'; Mask = '255.255.255.128'; First = '172.20.5.129'; Last = '172.20.5.254'; Bcast = '172.20.5.255'; Hosts = 126 }
            @{ In = '10.10.0.0/16'; Network = '10.10.0.0/16'; Mask = '255.255.0.0'; First = '10.10.0.1'; Last = '10.10.255.254'; Bcast = '10.10.255.255'; Hosts = 65534 }
            @{ In = '203.0.113.10/29'; Network = '203.0.113.8/29'; Mask = '255.255.255.248'; First = '203.0.113.9'; Last = '203.0.113.14'; Bcast = '203.0.113.15'; Hosts = 6 }
            @{ In = '10.10.30.5/30'; Network = '10.10.30.4/30'; Mask = '255.255.255.252'; First = '10.10.30.5'; Last = '10.10.30.6'; Bcast = '10.10.30.7'; Hosts = 2 }
            @{ In = '192.168.1.77/27'; Network = '192.168.1.64/27'; Mask = '255.255.255.224'; First = '192.168.1.65'; Last = '192.168.1.94'; Bcast = '192.168.1.95'; Hosts = 30 }
            @{ In = '10.0.0.1/31'; Network = '10.0.0.0/31'; Mask = '255.255.255.254'; First = '10.0.0.0'; Last = '10.0.0.1'; Bcast = '-'; Hosts = 2 }
            @{ In = '10.10.10.2/32'; Network = '10.10.10.2/32'; Mask = '255.255.255.255'; First = '10.10.10.2'; Last = '10.10.10.2'; Bcast = '-'; Hosts = 1 }
        )
        $failed = 0
        foreach ($c in $cases) {
            $r = Get-Subnet $c.In
            $ok = ($r.Network -eq $c.Network) -and ($r.SubnetMask -eq $c.Mask) -and ($r.FirstHost -eq $c.First) -and
                  ($r.LastHost -eq $c.Last) -and ($r.Broadcast -eq $c.Bcast) -and ($r.UsableHosts -eq $c.Hosts)
            if ($ok) { Write-Host "PASS $($c.In)" } else { $failed++; Write-Host "FAIL $($c.In): got $($r | ConvertTo-Json -Compress)" }
        }
        foreach ($bad in '10.10.20.300/24', '10.10.20.0/33', '10.10.20.0') {
            try { $null = Get-Subnet $bad; $failed++; Write-Host "FAIL invalid input accepted: $bad" }
            catch { Write-Host "PASS rejects $bad" }
        }
        if ($failed) { Write-Host "$failed test(s) failed"; exit 1 }
        Write-Host 'All subnet calculator tests passed.'
        exit 0
    }
}

process {
    foreach ($item in $Cidr) { Get-Subnet $item }
}
