#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Unit tests for the shared module. Run: ./07-powershell/tests/Invoke-TechCorpTests.ps1

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../modules/TechCorp.Admin/TechCorp.Admin.psd1') -Force
    $Now = [datetime]'2027-06-01T09:00:00'
}

Describe 'Get-TcRepoRoot / Import-TcData' {
    It 'finds the repository root from a nested folder' {
        $root = Get-TcRepoRoot -StartPath $PSScriptRoot
        Test-Path (Join-Path $root '00-company-overview') | Should -BeTrue
    }
    It 'throws outside the repository' {
        { Get-TcRepoRoot -StartPath $TestDrive } | Should -Throw '*Repository root not found*'
    }
    It 'imports every data set by short name' -ForEach @(
        @{ Name = 'employees'; Min = 20 }, @{ Name = 'inventory'; Min = 100 }, @{ Name = 'departments'; Min = 7 },
        @{ Name = 'groups'; Min = 10 }, @{ Name = 'ous'; Min = 20 }, @{ Name = 'server-roles'; Min = 4 }
    ) {
        @(Import-TcData $Name).Count | Should -BeGreaterOrEqual $Min
    }
    It 'every server-roles.csv host exists in the hardware inventory' {
        $hosts = @(Import-TcData inventory | ForEach-Object Hostname)
        foreach ($r in Import-TcData server-roles) { $hosts | Should -Contain $r.Hostname }
    }
}

Describe 'ConvertTo-TcOuDn' {
    It 'reverses the path into a DN' {
        ConvertTo-TcOuDn 'TechCorp/Users/IT' | Should -Be 'OU=IT,OU=Users,OU=TechCorp,DC=corp,DC=techcorp,DC=example'
    }
}

Describe 'ConvertTo-TcAsciiName' {
    It 'folds <In> to <Out>' -ForEach @(
        @{ In = 'Zo' + [char]0x00EB; Out = 'zoe' }
        @{ In = "O'Brien-Smith"; Out = 'obriensmith' }
        @{ In = 'Stra' + [char]0x00DF + 'e'; Out = 'strasse' }
        @{ In = 'Bj' + [char]0x00F8 + 'rn'; Out = 'bjorn' }
        @{ In = [char]0x0141 + 'ukasz'; Out = 'lukasz' }
        @{ In = 'Van der Berg'; Out = 'vanderberg' }
        @{ In = [string]([char]0x0393) + [char]0x03B9 + [char]0x03AC + [char]0x03BD + [char]0x03BD + [char]0x03B7 + [char]0x03C2; Out = '' }
    ) {
        ConvertTo-TcAsciiName $In | Should -BeExactly $Out
    }
}

Describe 'Get-TcUsername' {
    It 'builds firstname.lastname in lower case' {
        Get-TcUsername -FirstName 'Floch' -LastName 'Forster' | Should -BeExactly 'floch.forster'
    }
    It 'numbers a collision with an existing account' {
        Get-TcUsername -FirstName 'Eren' -LastName 'Yeager' -Existing 'eren.yeager' | Should -BeExactly 'eren.yeager2'
        Get-TcUsername -FirstName 'Eren' -LastName 'Yeager' -Existing 'eren.yeager', 'EREN.YEAGER2' | Should -BeExactly 'eren.yeager3'
    }
    It 'never exceeds 20 characters (sAMAccountName) and shortens the last name first' {
        $u = Get-TcUsername -FirstName 'Bartholomew' -LastName 'Montgomeryshire'
        $u.Length | Should -BeLessOrEqual 20
        $u | Should -BeLike 'bartholomew.*'
    }
    It 'keeps 20 characters including a collision suffix' {
        $first = Get-TcUsername -FirstName 'Bartholomew' -LastName 'Montgomeryshire'
        $second = Get-TcUsername -FirstName 'Bartholomew' -LastName 'Montgomeryshire' -Existing $first
        $second.Length | Should -BeLessOrEqual 20
        $second | Should -Match '2$'
        $second | Should -Not -Be $first
    }
    It 'handles a very long first name' {
        $u = Get-TcUsername -FirstName 'Maximilianalexander' -LastName 'Lee'
        $u.Length | Should -BeLessOrEqual 20
        $u | Should -Match '^[a-z]+\.[a-z]+$'
    }
    It 'is unique against every current employee' {
        $existing = @(Import-TcData employees | ForEach-Object Username)
        foreach ($e in Import-TcData employees) {
            Get-TcUsername -FirstName $e.FirstName -LastName $e.LastName -Existing $existing | Should -Not -BeIn $existing
        }
    }
    It 'matches the username already in employees.csv for every employee' {
        foreach ($e in Import-TcData employees) {
            Get-TcUsername -FirstName $e.FirstName -LastName $e.LastName | Should -BeExactly $e.Username
        }
    }
    It 'throws when nothing usable is left' {
        { Get-TcUsername -FirstName '123' -LastName 'Smith' } | Should -Throw '*Cannot build*'
    }
}

Describe 'Get-TcRandomPassword' {
    BeforeAll {
        function ConvertTo-Plain([securestring]$s) { (New-Object System.Net.NetworkCredential('', $s)).Password }
    }
    It 'returns a read-only SecureString of the requested length' {
        $p = Get-TcRandomPassword -Length 20
        $p | Should -BeOfType [securestring]
        $p.Length | Should -Be 20
        $p.IsReadOnly() | Should -BeTrue
    }
    It 'always contains upper, lower, digit and symbol and no look-alikes (100 samples)' {
        1..100 | ForEach-Object {
            $plain = ConvertTo-Plain (Get-TcRandomPassword)
            $plain | Should -MatchExactly '[A-Z]'
            $plain | Should -MatchExactly '[a-z]'
            $plain | Should -Match '[0-9]'
            $plain | Should -Match '[!#%+\-=?@]'
            $plain | Should -Not -MatchExactly '[0O1lI]'
        }
    }
    It 'does not repeat itself' {
        $set = @{}
        1..200 | ForEach-Object { $set[(ConvertTo-Plain (Get-TcRandomPassword))] = $true }
        $set.Count | Should -Be 200
    }
    It 'refuses passwords shorter than the domain minimum of 14' {
        { Get-TcRandomPassword -Length 8 } | Should -Throw
    }
}

Describe 'Get-TcPasswordExpiry' {
    BeforeAll {
        function New-Account($Name, $LastSet, [bool]$Enabled = $true, [bool]$Never = $false, $ExpiresOn = $null) {
            [pscustomobject]@{ SamAccountName = $Name; Enabled = $Enabled; PasswordLastSet = $LastSet; PasswordNeverExpires = $Never; ExpiresOn = $ExpiresOn }
        }
    }
    It 'notifies exactly on the thresholds 14, 7, 3, 1 and not in between' -ForEach @(
        @{ Days = 14; Notify = $true }, @{ Days = 13; Notify = $false }, @{ Days = 7; Notify = $true }, @{ Days = 5; Notify = $false },
        @{ Days = 3; Notify = $true }, @{ Days = 1; Notify = $true }, @{ Days = 0; Notify = $true }, @{ Days = 30; Notify = $false }
    ) {
        $acc = New-Account 'adm-x' $Now.AddDays(-365 + $Days)
        $r = Get-TcPasswordExpiry -Account $acc -MaxPasswordAge (New-TimeSpan -Days 365) -Now $Now
        $r.DaysLeft | Should -Be $Days
        $r.Notify | Should -Be $Notify
    }
    It 'reports an expired password and notifies' {
        $r = Get-TcPasswordExpiry -Account (New-Account 'adm-x' $Now.AddDays(-400)) -Now $Now
        $r.State | Should -Be 'Expired'
        $r.Notify | Should -BeTrue
    }
    It 'prefers AD''s computed expiry (fine-grained policy) over MaxPasswordAge' {
        $r = Get-TcPasswordExpiry -Account (New-Account 'adm-x' $Now.AddDays(-10) -ExpiresOn $Now.AddDays(7)) -MaxPasswordAge (New-TimeSpan -Days 999) -Now $Now
        $r.DaysLeft | Should -Be 7
        $r.Notify | Should -BeTrue
    }
    It 'skips disabled, never-expiring and must-change accounts' {
        $r = @(Get-TcPasswordExpiry -Account @(
            (New-Account 'a' $Now.AddDays(-400) -Enabled $false)
            (New-Account 'b' $Now.AddDays(-400) -Never $true)
            (New-Account 'c' $null)
        ) -Now $Now)
        $r.State | Should -Be @('Disabled', 'NeverExpires', 'MustChange')
        $r.Notify | Should -Not -Contain $true
    }
    It 'accepts CSV strings (True/False, ISO dates)' {
        $csv = [pscustomobject]@{ SamAccountName = 'adm-x'; Enabled = 'True'; PasswordLastSet = '2026-06-08'; PasswordNeverExpires = 'False' }
        (Get-TcPasswordExpiry -Account $csv -Now $Now).DaysLeft | Should -Be 7
    }
}

Describe 'Get-TcPasswordExpiryMessage' {
    It 'names the account, the days and contains no link' {
        $m = Get-TcPasswordExpiryMessage -Expiry ([pscustomobject]@{ SamAccountName = 'adm-eren.yeager'; State = 'ExpiringSoon'; DaysLeft = 7; ExpiresOn = $Now.AddDays(7) })
        $m.Subject | Should -Be 'Password for adm-eren.yeager expires in 7 days'
        $m.Body | Should -Match 'Tuesday 8 June 2027'
        $m.Body | Should -Not -Match 'https?://'
    }
    It 'uses singular for one day and a different subject when expired' {
        (Get-TcPasswordExpiryMessage -Expiry ([pscustomobject]@{ SamAccountName = 'a'; State = 'ExpiringSoon'; DaysLeft = 1; ExpiresOn = $Now })).Subject | Should -Match 'in 1 day$'
        (Get-TcPasswordExpiryMessage -Expiry ([pscustomobject]@{ SamAccountName = 'a'; State = 'Expired'; DaysLeft = -3; ExpiresOn = $Now })).Subject | Should -Match 'has expired'
    }
}

Describe 'Get-TcStaleAccount' {
    BeforeAll {
        function New-Acc($Name, $LastLogon, $Created, [bool]$Enabled = $true, [bool]$Never = $false, $Changed = $null) {
            [pscustomobject]@{ SamAccountName = $Name; Enabled = $Enabled; LastLogonDate = $LastLogon; WhenCreated = $Created; WhenChanged = $Changed; PasswordNeverExpires = $Never; DistinguishedName = "CN=$Name" }
        }
    }
    It 'flags only accounts that need attention' {
        $r = @(Get-TcStaleAccount -InactiveDays 45 -Now $Now -Account @(
            (New-Acc 'active' $Now.AddDays(-3) $Now.AddDays(-400))
            (New-Acc 'inactive' $Now.AddDays(-60) $Now.AddDays(-400))
            (New-Acc 'never' $null $Now.AddDays(-90))
            (New-Acc 'newstarter' $null $Now.AddDays(-5))
            (New-Acc 'noexpiry' $Now.AddDays(-1) $Now.AddDays(-400) -Never $true)
            (New-Acc 'leaver-old' $Now.AddDays(-90) $Now.AddDays(-400) -Enabled $false -Changed $Now.AddDays(-40))
            (New-Acc 'leaver-new' $Now.AddDays(-20) $Now.AddDays(-400) -Enabled $false -Changed $Now.AddDays(-10))
        ))
        $byName = @{}; $r | ForEach-Object { $byName[$_.Name] = $_.Findings }
        $byName.Keys | Sort-Object | Should -Be @('inactive', 'leaver-old', 'never', 'noexpiry')
        $byName['inactive'] | Should -Be 'Inactive'
        $byName['never'] | Should -Be 'NeverLoggedOn'
        $byName['noexpiry'] | Should -Be 'PasswordNeverExpires'
        $byName['leaver-old'] | Should -Be 'DisabledPastRetention'
    }
    It 'reports several findings on one account' {
        $r = Get-TcStaleAccount -Now $Now -Account (New-Acc 'both' $Now.AddDays(-100) $Now.AddDays(-400) -Never $true)
        $r.Findings | Should -Be 'Inactive, PasswordNeverExpires'
        $r.DaysSinceLogon | Should -Be 100
    }
    It 'honours the allow list for PasswordNeverExpires' {
        @(Get-TcStaleAccount -Now $Now -AllowNeverExpires 'svc-backup' -Account (New-Acc 'svc-backup' $Now $Now.AddDays(-400) -Never $true)).Count | Should -Be 0
    }
    It 'refuses thresholds below the lastLogonTimestamp replication window' {
        { Get-TcStaleAccount -Account @() -InactiveDays 7 } | Should -Throw
    }
    It 'works for computer objects (Name, no password flag)' {
        $pc = [pscustomobject]@{ Name = 'TC-LT-009'; Enabled = $true; LastLogonDate = $Now.AddDays(-80); WhenCreated = $Now.AddDays(-500) }
        (Get-TcStaleAccount -Account $pc -Now $Now).Name | Should -Be 'TC-LT-009'
    }
}

Describe 'Get-TcWarrantyStatus' {
    It 'adds WarrantyYears to the in-service date' {
        $r = Get-TcWarrantyStatus -Asset ([pscustomobject]@{ AssetTag = 'A'; Hostname = ''; Category = 'Laptop'; AssignedTo = ''; WarrantyYears = '3' }) -InServiceDate '2027-02-15' -Now $Now
        $r.WarrantyEnd | Should -Be ([datetime]'2030-02-15')
        $r.Warranty | Should -Be 'OK'
    }
    It 'classifies <Now2> as <Expect>' -ForEach @(
        @{ Now2 = '2029-12-01'; Expect = 'ExpiringSoon' }, @{ Now2 = '2030-02-16'; Expect = 'Expired' }, @{ Now2 = '2027-03-01'; Expect = 'OK' }
    ) {
        $a = [pscustomobject]@{ AssetTag = 'A'; Hostname = ''; Category = 'Laptop'; AssignedTo = ''; WarrantyYears = '3' }
        (Get-TcWarrantyStatus -Asset $a -InServiceDate '2027-02-15' -WarnDays 90 -Now $Now2).Warranty | Should -Be $Expect
    }
    It 'uses a per-asset InServiceDate column when present and reports NoWarranty for VMs' {
        $r = @(Get-TcWarrantyStatus -Now $Now -Asset @(
            [pscustomobject]@{ AssetTag = 'A'; Hostname = ''; Category = ''; AssignedTo = ''; WarrantyYears = '1'; InServiceDate = '2026-01-01' }
            [pscustomobject]@{ AssetTag = 'VM'; Hostname = ''; Category = ''; AssignedTo = ''; WarrantyYears = '' }
        ))
        $r[0].Warranty | Should -Be 'Expired'
        $r[1].Warranty | Should -Be 'NoWarranty'
    }
}

Describe 'Get-TcDiskStatus' {
    It 'grades volumes by free space' {
        $r = @(Get-TcDiskStatus -ComputerName 'TC-FS01' -Disk @(
            [pscustomobject]@{ DeviceID = 'C:'; Size = 100GB; FreeSpace = 50GB }
            [pscustomobject]@{ DeviceID = 'D:'; Size = 100GB; FreeSpace = 15GB }
            [pscustomobject]@{ DeviceID = 'E:'; Size = 100GB; FreeSpace = 5GB }
            [pscustomobject]@{ DeviceID = 'F:'; Size = 0; FreeSpace = 0 }
        ))
        $r.Status | Should -Be @('PASS', 'WARN', 'FAIL')
        $r[1].Target | Should -Be 'TC-FS01 D:'
        $r[1].Detail | Should -Match '^15% free'
    }
    It 'rejects a FAIL threshold above the WARN threshold' {
        { Get-TcDiskStatus -Disk @() -WarnPercent 10 -FailPercent 20 } | Should -Throw
    }
}

Describe 'Results and exit codes' {
    It 'worst status wins: <Statuses> -> <Overall> / exit <Code>' -ForEach @(
        @{ Statuses = @('PASS', 'PASS'); Overall = 'PASS'; Code = 0 }
        @{ Statuses = @('PASS', 'WARN', 'SKIP'); Overall = 'WARN'; Code = 1 }
        @{ Statuses = @('WARN', 'FAIL', 'PASS'); Overall = 'FAIL'; Code = 2 }
        @{ Statuses = @('SKIP'); Overall = 'SKIP'; Code = 0 }
    ) {
        $rows = @($Statuses | ForEach-Object { New-TcResult -Check 'c' -Target 't' -Status $_ })
        Get-TcOverallStatus -Result $rows | Should -Be $Overall
        Get-TcExitCode -Result $rows | Should -Be $Code
    }
    It 'handles an empty result set' {
        Get-TcOverallStatus -Result @() | Should -Be 'SKIP'
    }
    It 'rejects an unknown status' {
        { New-TcResult -Check 'c' -Target 't' -Status 'OK' } | Should -Throw
    }
}

Describe 'Write-TcLog' {
    It 'appends ISO-timestamped lines and creates the folder' {
        $log = Join-Path $TestDrive 'logs/sub/test.log'
        Write-TcLog -Message 'first' -Path $log -Now $Now | Out-Null
        Write-TcLog -Message 'second' -Level CHANGE -Path $log -Now $Now | Out-Null
        $lines = @(Get-Content $log)
        $lines.Count | Should -Be 2
        $lines[1] | Should -Match '^2027-06-01T09:00:00[+-]\d\d:\d\d \[CHANGE\] second$'
    }
}

Describe 'Get-TcOldFile' {
    BeforeAll {
        $dir = Join-Path $TestDrive 'old'
        New-Item -ItemType Directory -Path (Join-Path $dir 'sub') -Force | Out-Null
        foreach ($f in @(@('old.log', 100), @('new.log', 1), @('old.docx', 100), @('sub/old.csv', 100))) {
            $p = Join-Path $dir $f[0]
            Set-Content -Path $p -Value 'x'
            (Get-Item $p).LastWriteTime = $Now.AddDays(-$f[1])
        }
    }
    It 'selects by age and pattern, top folder only by default' {
        @(Get-TcOldFile -Path $dir -OlderThanDays 30 -Include '*.log' -Now $Now).Name | Should -Be @('old.log')
    }
    It 'recurses when asked' {
        @(Get-TcOldFile -Path $dir -OlderThanDays 30 -Include '*.log', '*.csv' -Recurse -Now $Now).Name | Sort-Object | Should -Be @('old.csv', 'old.log')
    }
    It 'throws for a missing folder' {
        { Get-TcOldFile -Path (Join-Path $TestDrive 'nope') -OlderThanDays 30 } | Should -Throw '*not found*'
    }
}

Describe 'Test-TcTcpPort' {
    It 'returns true for a listening port and false for a closed one' {
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        try {
            $port = $listener.LocalEndpoint.Port
            Test-TcTcpPort -ComputerName '127.0.0.1' -Port $port | Should -BeTrue
        }
        finally { $listener.Stop() }
        Test-TcTcpPort -ComputerName '127.0.0.1' -Port $port -TimeoutMs 500 | Should -BeFalse
    }
    It 'returns false for a name that does not resolve' {
        Test-TcTcpPort -ComputerName 'tc-does-not-exist.invalid' -Port 445 -TimeoutMs 500 | Should -BeFalse
    }
}

Describe 'ConvertFrom-TcStripchart' {
    It 'returns the median offset of the samples' {
        $lines = @(
            'Tracking tc-dc01 [10.10.30.11:123].'
            'Collecting 3 samples.'
            'The current time is 01/06/2027 09:00:00.'
            '09:00:00, +00.0120000s'
            '09:00:02, -00.5000000s'
            '09:00:04, +01.2500000s'
        )
        ConvertFrom-TcStripchart -Line $lines | Should -Be 0.012
    }
    It 'accepts a comma decimal separator (non-English Windows)' {
        ConvertFrom-TcStripchart -Line '09:00:00, +02,5000000s' | Should -Be 2.5
    }
    It 'returns null when the source did not answer' {
        ConvertFrom-TcStripchart -Line @('09:00:00, error: 0x800705B4') | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-TcHtmlReport' {
    It 'HTML-encodes every value (no script injection from AD attributes)' {
        $html = ConvertTo-TcHtmlReport -Title 'T<1>' -Now $Now -Section ([ordered]@{ 'S&1' = @([pscustomobject]@{ Name = '<script>alert(1)</script>'; Status = 'FAIL' }) })
        $html | Should -Not -Match '<script>'
        $html | Should -Match '&lt;script&gt;'
        $html | Should -Match '<title>T&lt;1&gt;</title>'
        $html | Should -Match '<h2>S&amp;1 \(1\)</h2>'
        $html | Should -Match '<td class="fail">FAIL</td>'
    }
    It 'says so when a section is empty and formats dates' {
        $html = ConvertTo-TcHtmlReport -Title 'T' -Now $Now -Section ([ordered]@{ 'Empty' = @(); 'Dates' = @([pscustomobject]@{ When = $Now }) })
        $html | Should -Match 'Nothing to report'
        $html | Should -Match '<td>2027-06-01</td>'
    }
}

Describe 'ConvertTo-TcBool / ConvertTo-TcDate' {
    It 'reads CSV booleans' {
        @('True', 'yes', '1', $true) | ForEach-Object { ConvertTo-TcBool $_ | Should -BeTrue }
        @('False', 'no', '0', '', $null, $false) | ForEach-Object { ConvertTo-TcBool $_ | Should -BeFalse }
    }
    It 'reads ISO dates independent of the PC culture and returns null for empty' {
        ConvertTo-TcDate '2027-06-01' | Should -Be ([datetime]'2027-06-01')
        ConvertTo-TcDate '' | Should -BeNullOrEmpty
        { ConvertTo-TcDate 'yesterday' } | Should -Throw
    }
}
