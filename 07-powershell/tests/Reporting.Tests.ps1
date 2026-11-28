#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Report scripts, run on fixture data (CSV exports / a copy of the repository data).

BeforeAll {
    $Reporting = Join-Path $PSScriptRoot '../reporting'
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $Now = [datetime]'2027-06-01T08:00:00'
}

Describe 'Get-TechCorpStaleAccountReport.ps1 -InputCsv' {
    BeforeAll {
        $csv = Join-Path $TestDrive 'ad-export.csv'
        @(
            'SamAccountName,Name,ObjectClass,Enabled,LastLogonDate,WhenCreated,WhenChanged,PasswordNeverExpires,DistinguishedName'
            'eren.yeager,Eren Yeager,user,True,2027-05-31,2027-02-01,2027-05-31,False,"CN=Eren Yeager,OU=IT,OU=Users,OU=TechCorp,DC=corp,DC=techcorp,DC=example"'
            'bertolt.hoover,Bertolt Hoover,user,True,2027-03-01,2027-02-01,2027-03-01,False,"CN=Bertolt Hoover,OU=Sales,OU=Users,OU=TechCorp,DC=corp,DC=techcorp,DC=example"'
            'test.user,Test User,user,True,,2027-02-01,2027-02-01,True,"CN=Test User,OU=IT,OU=Users,OU=TechCorp,DC=corp,DC=techcorp,DC=example"'
            'connie.springer,Connie Springer,user,False,2027-04-01,2027-02-01,2027-04-02,False,"CN=Connie Springer,OU=Disabled,OU=TechCorp,DC=corp,DC=techcorp,DC=example"'
            ',TC-LT-012,computer,True,2027-03-20,2027-02-01,2027-03-20,,"CN=TC-LT-012,OU=Standard,OU=Workstations,OU=Computers,OU=TechCorp,DC=corp,DC=techcorp,DC=example"'
            ',TC-LT-001,computer,True,2027-05-30,2027-02-01,2027-05-30,,"CN=TC-LT-001,OU=Standard,OU=Workstations,OU=Computers,OU=TechCorp,DC=corp,DC=techcorp,DC=example"'
        ) | Set-Content $csv -Encoding UTF8
        $out = Join-Path $TestDrive 'reports'
        $rows = @(& (Join-Path $Reporting 'Get-TechCorpStaleAccountReport.ps1') -InputCsv $csv -OutputFolder $out -Now $Now 6>$null)
        $exit = $LASTEXITCODE
    }
    It 'finds exactly the stale users and computers' {
        $rows.Name | Sort-Object | Should -Be @('bertolt.hoover', 'connie.springer', 'TC-LT-012', 'test.user')
        $exit | Should -Be 1
    }
    It 'gives the reason for each finding' {
        ($rows | Where-Object Name -eq 'test.user').Findings | Should -Be 'NeverLoggedOn, PasswordNeverExpires'
        ($rows | Where-Object Name -eq 'connie.springer').Findings | Should -Be 'DisabledPastRetention'
        ($rows | Where-Object Name -eq 'TC-LT-012').Type | Should -Be 'Computer'
    }
    It 'writes the CSV and HTML evidence' {
        Test-Path (Join-Path $out 'stale-accounts-2027-06-01.csv') | Should -BeTrue
        Get-Content (Join-Path $out 'stale-accounts-2027-06-01.html') -Raw | Should -Match 'bertolt.hoover'
    }
    It 'exits 0 when nothing is stale' {
        $clean = Join-Path $TestDrive 'clean.csv'
        Get-Content $csv -TotalCount 2 | Set-Content $clean
        & (Join-Path $Reporting 'Get-TechCorpStaleAccountReport.ps1') -InputCsv $clean -OutputFolder $out -Now $Now 6>$null | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'Send-TechCorpPasswordExpiryNotice.ps1 -InputCsv' {
    BeforeAll {
        $csv = Join-Path $TestDrive 'expiry.csv'
        @(
            'SamAccountName,DisplayName,EmailAddress,Enabled,PasswordLastSet,PasswordNeverExpires,ExpiresOn'
            'eren.yeager,Eren Yeager,eren.yeager@techcorp.example,True,2027-02-01,True,'
            'adm-eren.yeager,Eren Yeager (admin),,True,2026-06-08,False,2027-06-08'
            'wadm-eren.yeager,Eren Yeager (workstation admin),,True,2026-06-10,False,2027-06-10'
            'adm-hange.zoe,Hange Zoe (admin),,True,2026-05-01,False,2027-05-01'
        ) | Set-Content $csv -Encoding UTF8
        $out = Join-Path $TestDrive 'reports'
    }
    It 'reminds on the 7-day threshold and reports the expired account, without sending' {
        $due = @(& (Join-Path $Reporting 'Send-TechCorpPasswordExpiryNotice.ps1') -InputCsv $csv -OutputFolder $out -Now $Now 6>$null)
        $LASTEXITCODE | Should -Be 1
        $due.SamAccountName | Sort-Object | Should -Be @('adm-eren.yeager', 'adm-hange.zoe')
        ($due | Where-Object SamAccountName -eq 'adm-eren.yeager').DaysLeft | Should -Be 7
        $due.Sent | Should -Not -Contain 'Yes'
    }
    It 'sends admin-account reminders to the owner''s mailbox' {
        $due = @(& (Join-Path $Reporting 'Send-TechCorpPasswordExpiryNotice.ps1') -InputCsv $csv -OutputFolder $out -Now $Now 6>$null)
        ($due | Where-Object SamAccountName -eq 'adm-eren.yeager').Recipient | Should -Be 'eren.yeager@techcorp.example'
    }
    It 'marks accounts without a resolvable owner instead of failing' {
        $due = @(& (Join-Path $Reporting 'Send-TechCorpPasswordExpiryNotice.ps1') -InputCsv $csv -OutputFolder $out -SmtpServer 'smtp.invalid' -Now $Now -WhatIf 6>$null)
        ($due | Where-Object SamAccountName -eq 'adm-hange.zoe').Sent | Should -Be 'No recipient'
        ($due | Where-Object SamAccountName -eq 'adm-eren.yeager').Sent | Should -Be 'WhatIf'
    }
    It 'lists every expiring account (not only today''s reminders) in the CSV' {
        & (Join-Path $Reporting 'Send-TechCorpPasswordExpiryNotice.ps1') -InputCsv $csv -OutputFolder $out -Now $Now 6>$null | Out-Null
        @(Import-Csv (Join-Path $out 'password-expiry-2027-06-01.csv')).SamAccountName | Sort-Object |
            Should -Be @('adm-eren.yeager', 'adm-hange.zoe', 'wadm-eren.yeager')
    }
}

Describe 'Get-TechCorpInventoryReport.ps1' {
    BeforeAll {
        $inventoryScript = Join-Path $Reporting 'Get-TechCorpInventoryReport.ps1'
        # fixture: a copy of the repository data with a leaver's laptop not returned
        $fixture = Join-Path $TestDrive 'repo'
        foreach ($rel in '00-company-overview/data', '01-office-deployment/equipment-inventory', '07-powershell/data') {
            New-Item -ItemType Directory -Path (Join-Path $fixture $rel) -Force | Out-Null
        }
        Copy-Item (Join-Path $Root '07-powershell/data/server-roles.csv') (Join-Path $fixture '07-powershell/data/')
        $employees = @(Import-Csv (Join-Path $Root '00-company-overview/data/employees.csv') | Where-Object Username -ne 'connie.springer')
        $employees | Export-Csv (Join-Path $fixture '00-company-overview/data/employees.csv') -NoTypeInformation -Encoding UTF8
        Copy-Item (Join-Path $Root '01-office-deployment/equipment-inventory/hardware-inventory.csv') (Join-Path $fixture '01-office-deployment/equipment-inventory/')
    }
    It 'reports no problems for the repository data at go-live' {
        $rows = @(& $inventoryScript -Root $Root -OutputFolder (Join-Path $TestDrive 'ok') -Now '2027-03-01' 6>$null)
        $LASTEXITCODE | Should -Be 0
        @($rows | Where-Object Status -ne 'PASS').Count | Should -Be 0
    }
    It 'warns about warranties ending within 90 days' {
        $rows = @(& $inventoryScript -Root $Root -OutputFolder (Join-Path $TestDrive 'w') -Now '2029-12-01' 6>$null)
        $LASTEXITCODE | Should -Be 1
        ($rows | Where-Object Target -eq 'TC-FW01').Detail | Should -Match '^ExpiringSoon - ends 2030-02-15'
        $rows | Where-Object Target -eq 'TC-SW01' | Should -BeNullOrEmpty   # 5-year warranty
    }
    It 'fails on a laptop still assigned to a leaver' {
        $rows = @(& $inventoryScript -Root $fixture -OutputFolder (Join-Path $TestDrive 'leaver') -Now '2027-03-01' 6>$null)
        $LASTEXITCODE | Should -Be 2
        $fail = @($rows | Where-Object Status -eq 'FAIL')
        $fail.Target | Should -Be @('TC-LT-009')
        $fail[0].Detail | Should -Match 'connie.springer'
    }
    It 'warns when the spare stock is below the minimum' {
        $rows = @(& $inventoryScript -Root $Root -OutputFolder (Join-Path $TestDrive 's') -MinSpareLaptops 3 -Now '2027-03-01' 6>$null)
        ($rows | Where-Object Check -eq 'Spare laptops').Status | Should -Be 'WARN'
    }
    It 'writes an HTML report with the category summary' {
        & $inventoryScript -Root $Root -OutputFolder (Join-Path $TestDrive 'html') -Now '2027-03-01' 6>$null | Out-Null
        $html = Get-Content (Join-Path $TestDrive 'html/inventory-2027-03-01.html') -Raw
        $html | Should -Match '<h2>Assets by category'
        $html | Should -Match '<td>Laptop</td><td>22</td>'
    }
}
