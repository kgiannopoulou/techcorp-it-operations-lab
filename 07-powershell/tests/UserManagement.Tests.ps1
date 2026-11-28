#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Joiner / leaver scripts. Active Directory, Graph and Exchange Online are
# replaced by stub functions + Pester mocks, so these run on any OS in CI and
# prove WHAT the scripts would change, in WHICH order - not that AD accepts it
# (that is the M5 lab).

BeforeAll {
    $Scripts = Join-Path $PSScriptRoot '../user-management'
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $Domain = 'DC=corp,DC=techcorp,DC=example'

    # Stubs: the real cmdlets do not exist on the CI runner. Same parameter names as the real ones.
    # Because Get-ADUser now exists, the scripts skip Import-Module ActiveDirectory.
    function Get-ADUser { param($Identity, $Filter, $Properties, $Server, $SearchBase) }
    function New-ADUser { param($Name, $SamAccountName, $UserPrincipalName, $GivenName, $Surname, $DisplayName, $EmailAddress, $EmployeeID, $Department, $Title, $Company, $Manager, $Path, $AccountPassword, $ChangePasswordAtLogon, $Enabled, $Server) }
    function Add-ADGroupMember { param($Identity, $Members, $Server) }
    function Get-ADPrincipalGroupMembership { param($Identity, $Server) }
    function Disable-ADAccount { param($Identity, $Server) }
    function Set-ADAccountPassword { param($Identity, [switch]$Reset, $NewPassword, $Server) }
    function Set-ADUser { param($Identity, $Description, $Server) }
    function Remove-ADGroupMember { [CmdletBinding(SupportsShouldProcess)] param($Identity, $Members, $Server) }
    function Move-ADObject { param($Identity, $TargetPath, $Server) }
    function Revoke-MgUserSignInSession { param($UserId) }
    function Set-Mailbox { param($Identity, $Type) }
    function Add-MailboxPermission { param($Identity, $User, $AccessRights, $InheritanceType) }
    function Set-MailboxAutoReplyConfiguration { param($Identity, $AutoReplyState, $InternalMessage, $ExternalMessage) }
}

Describe 'New-TechCorpUser.ps1 -PlanOnly' {
    BeforeAll {
        $out = Join-Path $TestDrive 'onboarding.csv'
        $common = @{ PlanOnly = $true; OutputPath = $out; LogPath = (Join-Path $TestDrive 'new.log'); Now = [datetime]'2027-02-20' }
        $plans = @(& (Join-Path $Scripts 'New-TechCorpUser.ps1') -Path (Join-Path $Scripts 'new-starters.example.csv') @common 6>$null)
    }
    It 'plans every row of the example request' {
        $plans.Count | Should -Be 2
        $plans.SamAccountName | Should -Be @('floch.forster', 'gabi.braun')
    }
    It 'continues the employee ID sequence after employees.csv' {
        $plans.EmployeeID | Should -Be @('E021', 'E022')
    }
    It 'derives OU and groups from department-map.csv and ad-groups.csv' {
        $plans[0].OuDn | Should -Be "OU=Sales,OU=Users,OU=TechCorp,$Domain"
        $plans[0].Groups | Should -Be 'GG_Sales_Users;LIC_M365_BusinessPremium'
        $plans[1].Groups | Should -Be 'GG_Development_Users;LIC_M365_BusinessPremium'
    }
    It 'issues each spare laptop once' {
        $plans.AssetTag | Should -Be @('TC-LT-021', 'TC-LT-022')
    }
    It 'creates future starters disabled' {
        $plans.EnabledAtCreation | Should -Not -Contain $true
    }
    It 'writes the record without any password column' {
        $record = @(Import-Csv $out)
        $record.Count | Should -Be 2
        $record[0].PSObject.Properties.Name | Where-Object { $_ -match 'pass' } | Should -BeNullOrEmpty
    }
    It 'produces an employees.csv row with the same columns as the file' {
        $header = (Get-Content (Join-Path $Root '00-company-overview/data/employees.csv') -TotalCount 1).Split(',').Count
        $row = $plans[0].EmployeesCsvRow | ConvertFrom-Csv -Header (1..$header)
        $row.'4' | Should -Be 'floch.forster'
        $row.'5' | Should -Be 'Sales & Marketing'
        @($row.PSObject.Properties).Count | Should -Be $header
    }
    It 'numbers a name that already exists in employees.csv' {
        $p = & (Join-Path $Scripts 'New-TechCorpUser.ps1') -FirstName 'Mikasa' -LastName 'Ackerman' -Department 'IT' -JobTitle 'Intern' `
            -Manager 'eren.yeager' -StartDate '2027-02-20' @common 6>$null
        $p.SamAccountName | Should -Be 'mikasa.ackerman2'
        $p.EnabledAtCreation | Should -BeTrue
        $p.OuPath | Should -Be 'TechCorp/Users/IT'
    }
    It 'rejects an invalid request with every reason and does nothing' {
        { & (Join-Path $Scripts 'New-TechCorpUser.ps1') -FirstName 'Ymir' -LastName 'Fritz' -Department 'Titans' -JobTitle 'x' `
            -Manager 'nobody' -StartDate '2027-02-20' @common 6>$null 3>$null } | Should -Throw '*No valid new starters*'
    }
    It 'keeps valid rows and exits 1 when some rows are rejected' {
        $csv = Join-Path $TestDrive 'mixed.csv'
        @(
            'FirstName,LastName,Department,JobTitle,Manager,StartDate'
            'Falco,Grice,Customer Support,Support Specialist,petra.ral,2027-03-01'
            'Bad,Row,Customer Support,,petra.ral,not-a-date'
        ) | Set-Content $csv
        $p = @(& (Join-Path $Scripts 'New-TechCorpUser.ps1') -Path $csv @common 6>$null 3>$null)
        $LASTEXITCODE | Should -Be 1
        $p.SamAccountName | Should -Be 'falco.grice'
    }
}

Describe 'New-TechCorpUser.ps1 against (mocked) Active Directory' {
    BeforeAll {
        $common = @{ OutputPath = (Join-Path $TestDrive 'onb.csv'); LogPath = (Join-Path $TestDrive 'new.log'); Now = [datetime]'2027-02-20'; Confirm = $false }
        $captured = @{}
    }
    BeforeEach {
        Mock Get-ADUser -MockWith {
            if ($Identity) { return [pscustomobject]@{ SamAccountName = $Identity; DistinguishedName = "CN=$Identity,OU=Sales,OU=Users,OU=TechCorp,$Domain" } }
            if ($Filter -like "*-like 'floch.forster*'*") { return [pscustomobject]@{ SamAccountName = 'floch.forster' } }   # an old account
        }
        Mock New-ADUser -MockWith { $captured['password'] = (New-Object System.Net.NetworkCredential('', $AccountPassword)).Password }
        Mock Add-ADGroupMember -MockWith { }
    }
    It 'avoids a logon name that only exists in AD, creates the account and adds the groups' {
        $p = & (Join-Path $Scripts 'New-TechCorpUser.ps1') -FirstName 'Floch' -LastName 'Forster' -Department 'Sales & Marketing' `
            -JobTitle 'Account Executive' -Manager 'jean.kirstein' -StartDate '2027-03-01' @common 6>$null
        $p.SamAccountName | Should -Be 'floch.forster2'
        $p.Result | Should -Be 'Created'
        Should -Invoke New-ADUser -Times 1 -Exactly -ParameterFilter {
            $SamAccountName -eq 'floch.forster2' -and $Path -eq "OU=Sales,OU=Users,OU=TechCorp,$Domain" -and
            $Enabled -eq $false -and $ChangePasswordAtLogon -eq $true -and $AccountPassword -is [securestring] -and
            $Manager -like 'CN=jean.kirstein,*' -and $EmployeeID -eq 'E021'
        }
        Should -Invoke Add-ADGroupMember -Times 2 -Exactly
        Should -Invoke Add-ADGroupMember -Times 1 -Exactly -ParameterFilter { $Identity -eq 'LIC_M365_BusinessPremium' -and $Members -eq 'floch.forster2' }
    }
    It 'changes nothing under -WhatIf' {
        $p = & (Join-Path $Scripts 'New-TechCorpUser.ps1') -FirstName 'Floch' -LastName 'Forster' -Department 'Sales & Marketing' `
            -JobTitle 'Account Executive' -Manager 'jean.kirstein' -StartDate '2027-03-01' @common -WhatIf 6>$null
        $p.Result | Should -Be 'WhatIf'
        Should -Invoke New-ADUser -Times 0
        Should -Invoke Add-ADGroupMember -Times 0
    }
    It 'never writes the one-time password to the record or the log' {
        & (Join-Path $Scripts 'New-TechCorpUser.ps1') -FirstName 'Floch' -LastName 'Forster' -Department 'Sales & Marketing' `
            -JobTitle 'Account Executive' -Manager 'jean.kirstein' -StartDate '2027-03-01' @common 6>$null | Out-Null
        $captured['password'] | Should -Not -BeNullOrEmpty
        $text = (Get-Content $common.OutputPath -Raw) + (Get-Content $common.LogPath -Raw)
        $text.Contains($captured['password']) | Should -BeFalse
    }
}

Describe 'Disable-TechCorpUser.ps1' {
    BeforeAll {
        $calls = New-Object System.Collections.Generic.List[string]
        $fixture = @{ UserDn = ''; Groups = @() }   # mutated, never re-assigned: shared by BeforeEach, It and the mocks
        $leaver = Join-Path $Scripts 'Disable-TechCorpUser.ps1'
        $common = @{ Ticket = 'HD-2027-0042'; LeaveDate = [datetime]'2027-06-01'; RecordPath = (Join-Path $TestDrive 'leavers.csv'); LogPath = (Join-Path $TestDrive 'leaver.log'); Confirm = $false }
        $userDn = "CN=Connie Springer,OU=Sales,OU=Users,OU=TechCorp,$Domain"
    }
    BeforeEach {
        $calls.Clear()
        Mock Get-ADUser -MockWith {
            if ($Identity -like 'CN=Jean*') { return [pscustomobject]@{ SamAccountName = 'jean.kirstein'; UserPrincipalName = 'jean.kirstein@techcorp.example' } }
            [pscustomobject]@{
                SamAccountName = $Identity; DisplayName = 'Connie Springer'; UserPrincipalName = "$Identity@techcorp.example"
                DistinguishedName = $fixture.UserDn; Enabled = $true; Description = 'Account Executive'
                Manager = "CN=Jean Kirstein,OU=Sales,OU=Users,OU=TechCorp,$Domain"; PrimaryGroup = "CN=Domain Users,CN=Users,$Domain"
            }
        }
        Mock Get-ADPrincipalGroupMembership -MockWith {
            foreach ($g in $fixture.Groups) { [pscustomobject]@{ Name = $g; DistinguishedName = "CN=$g,OU=Role,OU=Groups,OU=TechCorp,$Domain" } }
            [pscustomobject]@{ Name = 'Domain Users'; DistinguishedName = "CN=Domain Users,CN=Users,$Domain" }
        }
        Mock Disable-ADAccount -MockWith { $calls.Add('Disable') }
        Mock Set-ADAccountPassword -MockWith { $calls.Add('ResetPassword'); $fixture.ResetLength = $NewPassword.Length }   # the script disposes it right after
        Mock Set-ADUser -MockWith { $calls.Add('Description') }
        Mock Remove-ADGroupMember -MockWith { $calls.Add("Remove:$($Identity.Name)") }
        Mock Move-ADObject -MockWith { $calls.Add('Move') }
        Mock Revoke-MgUserSignInSession -MockWith { $calls.Add('Revoke') }
        Mock Set-Mailbox -MockWith { $calls.Add('Shared') }
        Mock Add-MailboxPermission -MockWith { $calls.Add('FullAccess') }
        Mock Set-MailboxAutoReplyConfiguration -MockWith { $calls.Add('AutoReply') }
        $fixture.UserDn = $userDn
        $fixture.Groups = @('GG_Sales_Users', 'LIC_M365_BusinessPremium')
    }

    It 'runs the leaver steps in the documented order' {
        $steps = @(& $leaver -Identity 'connie.springer' -IncludeCloud @common)
        $LASTEXITCODE | Should -Be 0
        $calls | Should -Be @('Revoke', 'Shared', 'FullAccess', 'AutoReply', 'Disable', 'ResetPassword', 'Description',
            'Remove:GG_Sales_Users', 'Remove:LIC_M365_BusinessPremium', 'Move')
        ($steps | Where-Object Step -eq 'Safety check').Status | Should -Be 'PASS'
        @($steps | Where-Object Status -eq 'MANUAL').Count | Should -Be 2
    }
    It 'never removes Domain Users (primary group)' {
        & $leaver -Identity 'connie.springer' @common | Out-Null
        $calls | Should -Not -Contain 'Remove:Domain Users'
    }
    It 'writes the group record before removing anything' {
        & $leaver -Identity 'connie.springer' @common | Out-Null
        $rec = @(Import-Csv $common.RecordPath)[-1]
        $rec.Groups | Should -Be 'GG_Sales_Users;LIC_M365_BusinessPremium'
        $rec.OriginalOu | Should -Be "OU=Sales,OU=Users,OU=TechCorp,$Domain"
        $rec.Manager | Should -Be 'jean.kirstein'
        $rec.Ticket | Should -Be 'HD-2027-0042'
    }
    It 'sets a searchable description and moves to the Disabled OU' {
        & $leaver -Identity 'connie.springer' @common | Out-Null
        Should -Invoke Set-ADUser -Times 1 -Exactly -ParameterFilter { $Description -eq 'Left 2027-06-01 HD-2027-0042; groups: GG_Sales_Users, LIC_M365_BusinessPremium' }
        Should -Invoke Move-ADObject -Times 1 -Exactly -ParameterFilter { $TargetPath -eq "OU=Disabled,OU=TechCorp,$Domain" }
        Should -Invoke Set-ADAccountPassword -Times 1 -Exactly -ParameterFilter { $Reset -and $NewPassword -is [securestring] }
        $fixture.ResetLength | Should -Be 32
    }
    It 'stops before removing the licence group when the mailbox could not be converted' {
        Mock Set-Mailbox -MockWith { throw 'mailbox not found' }
        $steps = @(& $leaver -Identity 'connie.springer' -IncludeCloud @common)
        $LASTEXITCODE | Should -Be 2
        $calls | Should -Not -Contain 'Remove:LIC_M365_BusinessPremium'
        $calls | Should -Not -Contain 'Disable'
        ($steps | Where-Object Step -eq 'Mailbox to shared').Status | Should -Be 'Failed'
    }
    It 'refuses <Name> (<Why>)' -ForEach @(
        @{ Name = 'adm-eren.yeager'; Dn = "CN=adm-eren.yeager,OU=Accounts,OU=Admin,OU=TechCorp,$Domain"; Groups = @(); Why = 'admin account' }
        @{ Name = 'levi.ackerman'; Dn = "CN=Levi Ackerman,OU=Development,OU=Users,OU=TechCorp,$Domain"; Groups = @('Domain Admins'); Why = 'Domain Admins member' }
        @{ Name = 'administrator'; Dn = "CN=Administrator,CN=Users,$Domain"; Groups = @(); Why = 'built-in account' }
    ) {
        $fixture.UserDn = $Dn
        $fixture.Groups = $Groups
        $steps = @(& $leaver -Identity $Name @common)
        $LASTEXITCODE | Should -Be 2
        $steps[0].Status | Should -Be 'Refused'
        $calls.Count | Should -Be 0
    }
    It 'changes nothing under -WhatIf and writes no record' {
        $record = Join-Path $TestDrive 'whatif.csv'
        $params = $common.Clone(); $params.RecordPath = $record   # 5.1 rejects a splatted parameter given twice
        $steps = @(& $leaver -Identity 'connie.springer' -IncludeCloud @params -WhatIf)
        $calls.Count | Should -Be 0
        Test-Path $record | Should -BeFalse
        @($steps | Where-Object Status -eq 'WhatIf').Count | Should -BeGreaterThan 5
    }
    It 'requires a ticket number in the helpdesk format' {
        { & $leaver -Identity 'connie.springer' -Ticket 'asap' -RecordPath $common.RecordPath -LogPath $common.LogPath -Confirm:$false } | Should -Throw
    }
}
