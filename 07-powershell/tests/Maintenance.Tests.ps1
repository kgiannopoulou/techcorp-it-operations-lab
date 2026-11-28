#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Maintenance and network scripts: real files in TestDrive, a real TCP listener on loopback.

BeforeDiscovery {
    $onWindows = [Environment]::OSVersion.Platform -eq 'Win32NT'
}

BeforeAll {
    $Ps = Join-Path $PSScriptRoot '..'
    $Now = [datetime]'2027-06-01T08:00:00'
}

Describe 'Remove-TechCorpOldFile.ps1' {
    BeforeEach {
        $dir = Join-Path $TestDrive "clean-$([guid]::NewGuid().ToString('N').Substring(0, 6))"
        New-Item -ItemType Directory -Path (Join-Path $dir 'sub') -Force | Out-Null
        foreach ($f in @(@('old.log', 120), @('new.log', 2), @('old.docx', 120), @('sub/old.csv', 120), @('sub/new.csv', 2))) {
            $p = Join-Path $dir $f[0]
            Set-Content -Path $p -Value ('x' * 2048)
            (Get-Item $p).LastWriteTime = $Now.AddDays(-$f[1])
        }
        $log = Join-Path $TestDrive 'clean.log'
        $cleaner = Join-Path $Ps 'maintenance/Remove-TechCorpOldFile.ps1'
    }
    It 'deletes only old files that match -Include, recursively, and keeps the rest' {
        $r = & $cleaner -Path $dir -OlderThanDays 90 -Recurse -LogPath $log -Now $Now -Confirm:$false
        $r.Deleted | Should -Be 2
        $r.Status | Should -Be 'Done'
        @(Get-ChildItem $dir -Recurse -File).Name | Sort-Object | Should -Be @('new.csv', 'new.log', 'old.docx')
        Get-Content $log -Raw | Should -Match '2 of 2 file\(s\) older than 90 days deleted'
    }
    It 'deletes nothing under -WhatIf' {
        $r = & $cleaner -Path $dir -OlderThanDays 90 -Recurse -LogPath $log -Now $Now -WhatIf
        $r.Status | Should -Be 'WhatIf'
        $r.Files | Should -Be 2
        @(Get-ChildItem $dir -Recurse -File).Count | Should -Be 5
    }
    It 'does not recurse unless asked' {
        $r = & $cleaner -Path $dir -OlderThanDays 90 -LogPath $log -Now $Now -Confirm:$false
        $r.Deleted | Should -Be 1
        Test-Path (Join-Path $dir 'sub/old.csv') | Should -BeTrue
    }
    It 'removes folders left empty when asked' {
        Remove-Item (Join-Path $dir 'sub/new.csv')
        & $cleaner -Path $dir -OlderThanDays 90 -Recurse -RemoveEmptyFolders -LogPath $log -Now $Now -Confirm:$false | Out-Null
        Test-Path (Join-Path $dir 'sub') | Should -BeFalse
    }
    It 'refuses a drive root and the repository itself' {
        $driveRoot = [IO.Path]::GetPathRoot($TestDrive)
        $repo = (Resolve-Path (Join-Path $Ps '..')).Path
        $r = @(& $cleaner -Path $driveRoot, $repo -OlderThanDays 1 -LogPath $log -Now $Now -WhatIf 2>$null)
        $r.Status | Should -Be @('Refused', 'Refused')
        $LASTEXITCODE | Should -Be 1
    }
    It 'reports a missing folder without failing' {
        $r = & $cleaner -Path (Join-Path $TestDrive 'missing') -OlderThanDays 30 -LogPath $log -Now $Now -WhatIf 3>$null
        $r.Status | Should -Be 'NotFound'
    }
}

Describe 'Test-TechCorpServicePort.ps1' {
    BeforeAll {
        $porter = Join-Path $Ps 'network-diagnostics/Test-TechCorpServicePort.ps1'
    }
    It 'PASSes an open port and FAILs a closed one' {
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        try {
            $open = $listener.LocalEndpoint.Port
            $rows = @(& $porter -Target @{ Hostname = 'loopback'; Address = '127.0.0.1'; TcpPorts = "$open;1" } -TimeoutMs 500 6>$null)
            $code = $LASTEXITCODE
        }
        finally { $listener.Stop() }
        $rows.Status | Should -Be @('PASS', 'FAIL')
        $code | Should -Be 2
    }
    It 'FAILs DNS and skips the ports when a name does not resolve' {
        $rows = @(& $porter -Target @{ Hostname = 'tc-nope.invalid'; Address = ''; TcpPorts = '445' } 6>$null)
        $rows.Check | Should -Be 'DNS'
        $rows.Status | Should -Be 'FAIL'
    }
    It 'builds its targets from server-roles.csv and the inventory addresses' {
        $rows = @(& $porter -ComputerName 'TC-FS01' -TimeoutMs 100 6>$null)
        $rows.Target | Select-Object -Unique | Should -Be 'TC-FS01'
        $rows.Check | Should -Contain 'Port 445 SMB'
        $rows[0].Detail | Should -Match '^10\.10\.30\.20:'
    }
    It 'throws for an unknown host name' {
        { & $porter -ComputerName 'TC-NOPE' 6>$null } | Should -Throw '*No targets*'
    }
}

Describe 'Get-TechCorpServerHealth.ps1 on this computer' -Skip:(-not $onWindows) {
    BeforeAll {
        $rows = @(& (Join-Path $Ps 'maintenance/Get-TechCorpServerHealth.ps1') -OutputFolder (Join-Path $TestDrive 'h') 6>$null)
        $code = $LASTEXITCODE
    }
    It 'runs every check and returns valid statuses' {
        $rows.Check | Should -Contain 'Uptime'
        $rows.Check | Should -Contain 'Disk free space'
        $rows.Check | Should -Contain 'Pending reboot'
        $rows.Check | Should -Contain 'Automatic services'
        $rows.Check | Should -Contain 'System log'
        $rows.Status | ForEach-Object { $_ | Should -BeIn 'PASS', 'WARN', 'FAIL', 'SKIP' }
    }
    It 'returns the exit code that matches the worst status' {
        Import-Module (Join-Path $Ps 'modules/TechCorp.Admin/TechCorp.Admin.psd1') -Force
        $code | Should -Be (Get-TcExitCode -Result $rows)
    }
    It 'reports an unreachable computer as FAIL instead of stopping' {
        $r = @(& (Join-Path $Ps 'maintenance/Get-TechCorpServerHealth.ps1') -ComputerName 'tc-nope.invalid' -OutputFolder (Join-Path $TestDrive 'h') 6>$null)
        $r[0].Check | Should -Be 'Reachable'
        $r[0].Status | Should -Be 'FAIL'
    }
}

Describe 'Invoke-TechCorpDailyCheck.ps1 on this computer' -Skip:(-not $onWindows) {
    It 'combines the steps into one report and SKIPs AD steps when asked' {
        $out = Join-Path $TestDrive 'daily'
        $summary = @(& (Join-Path $Ps 'maintenance/Invoke-TechCorpDailyCheck.ps1') -ComputerName $env:COMPUTERNAME -SkipPorts -SkipAd -OutputFolder $out -Now $Now 6>$null)
        $summary.Step | Should -Be @('Server health', 'Service ports', 'Stale accounts', 'Password expiry')
        ($summary | Where-Object Step -eq 'Stale accounts').Status | Should -Be 'SKIP'
        Test-Path (Join-Path $out 'daily-check-2027-06-01.html') | Should -BeTrue
    }
}
