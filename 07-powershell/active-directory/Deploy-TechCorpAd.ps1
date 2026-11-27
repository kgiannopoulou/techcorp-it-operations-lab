<#
.SYNOPSIS
    Creates or updates TechCorp's OUs, groups, user accounts, admin accounts,
    group memberships, delegation and admin password policy in Active Directory.

.DESCRIPTION
    Idempotent: every object is looked up first and only created or updated
    when it differs from the plan produced by Get-TechCorpAdPlan.ps1 (which
    reads the CSV files in 03-windows-server). Run it again after changing a
    CSV and only the difference is applied.

    Steps:
      0. Alternative UPN suffix techcorp.example (needed for Entra Connect)
      1. OUs (protected from accidental deletion)
      2. Security groups (GG_ global, DL_ domain local)
      3. Staff accounts from employees.csv (initial password, must change at first logon)
      4. Manager attribute
      5. Privileged accounts adm- / wadm- (not delegable, adm- in Protected Users)
      6. Group memberships (missing members added; unexpected members reported,
         removed only with -RemoveUnexpectedMembers)
      7. Delegation: helpdesk password reset/unlock, workstation admins join computers
      8. Fine-grained password policy PSO-AdminAccounts
      9. ms-DS-MachineAccountQuota = 0 (ordinary users cannot join computers)

    Run on TC-DC01 (or a machine with RSAT AD tools) as adm-eren.yeager.
    Supports -WhatIf and -Confirm. Never writes passwords to disk or output.

.PARAMETER InitialPassword
    Initial password for NEW accounts only (existing accounts are not touched).
    Every new account must change it at first sign-in. Prompted if omitted.

.PARAMETER RemoveUnexpectedMembers
    Remove group members that are not in the plan (default: report only).

.PARAMETER Server
    Domain controller to target (default: any DC of the current domain).

.PARAMETER ReportPath
    Optional CSV file for the list of actions taken (evidence).

.EXAMPLE
    .\Deploy-TechCorpAd.ps1 -WhatIf
    Shows what would be created without changing anything.

.EXAMPLE
    .\Deploy-TechCorpAd.ps1 -ReportPath C:\Evidence\ad-deploy.csv
#>
#Requires -Modules ActiveDirectory
[CmdletBinding(SupportsShouldProcess)]
param(
    [securestring]$InitialPassword,

    [switch]$RemoveUnexpectedMembers,

    [string]$Server,

    [string]$ReportPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$plan = & (Join-Path $PSScriptRoot 'Get-TechCorpAdPlan.ps1')
$adParams = @{}
if ($Server) { $adParams['Server'] = $Server }

$domain = Get-ADDomain @adParams
if ($domain.DistinguishedName -ne $plan.DomainDn) {
    throw "Connected to $($domain.DistinguishedName) but the plan is for $($plan.DomainDn)."
}
$netbios = $domain.NetBIOSName

$script:Log = New-Object System.Collections.Generic.List[object]
function Write-Step([string]$Step, [string]$Object, [string]$Result) {
    $script:Log.Add([pscustomobject]@{ Time = (Get-Date).ToString('s'); Step = $Step; Object = $Object; Result = $Result })
    $colour = switch -Wildcard ($Result) { 'created*' { 'Green' } 'updated*' { 'Cyan' } 'added*' { 'Green' } 'removed*' { 'Yellow' } 'WARN*' { 'Yellow' } default { 'Gray' } }
    Write-Host ('{0,-12} {1,-45} {2}' -f $Step, $Object, $Result) -ForegroundColor $colour
}

function Test-AdObject([string]$DistinguishedName) {
    try { $null = Get-ADObject -Identity $DistinguishedName @adParams; return $true }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] { return $false }
}

function Get-ParentDn([string]$DistinguishedName) {
    return ($DistinguishedName -replace '^.+?(?<!\\),', '')
}

$newAccounts = @($plan.Users + $plan.AdminAccounts | Where-Object {
    -not (Get-ADUser -Filter "SamAccountName -eq '$($_.SamAccountName)'" @adParams)
})
if ($newAccounts.Count -gt 0 -and -not $InitialPassword -and -not $WhatIfPreference) {
    $InitialPassword = Read-Host -AsSecureString "Initial password for $($newAccounts.Count) new account(s)"
}

# 0. UPN suffix --------------------------------------------------------------
# Staff UPNs use the e-mail domain; registering it as an alternative UPN suffix
# makes it selectable in ADUC and lets Entra Connect match it to the verified domain.
$forest = Get-ADForest @adParams
if ($plan.UpnSuffix -notin $forest.UPNSuffixes -and $PSCmdlet.ShouldProcess($forest.Name, "Add UPN suffix $($plan.UpnSuffix)")) {
    Set-ADForest -Identity $forest.Name -UPNSuffixes @{ Add = $plan.UpnSuffix } @adParams
    Write-Step 'Forest' 'UPN suffix' "updated (added $($plan.UpnSuffix))"
}

# 1. OUs ---------------------------------------------------------------------
foreach ($ou in ($plan.OUs | Sort-Object { $_.Path.Split('/').Count })) {
    if (Test-AdObject $ou.DistinguishedName) { Write-Step 'OU' $ou.Path 'exists'; continue }
    if ($PSCmdlet.ShouldProcess($ou.DistinguishedName, 'Create OU')) {
        New-ADOrganizationalUnit -Name $ou.Name -Path $ou.ParentDn -Description $ou.Description -ProtectedFromAccidentalDeletion $true @adParams
        Write-Step 'OU' $ou.Path 'created'
    }
}

# 2. Groups ------------------------------------------------------------------
foreach ($g in $plan.Groups) {
    $existing = Get-ADGroup -Filter "Name -eq '$($g.Name)'" @adParams
    if ($existing) {
        if ($existing.GroupScope.ToString() -ne $g.Scope) { Write-Step 'Group' $g.Name "WARN scope is $($existing.GroupScope), plan says $($g.Scope) - fix manually" }
        elseif ((Get-ParentDn $existing.DistinguishedName) -ne $g.OuDn -and $PSCmdlet.ShouldProcess($g.Name, "Move to $($g.OuDn)")) {
            Move-ADObject -Identity $existing.DistinguishedName -TargetPath $g.OuDn @adParams
            Write-Step 'Group' $g.Name 'updated (moved)'
        }
        else { Write-Step 'Group' $g.Name 'exists' }
        continue
    }
    if ($PSCmdlet.ShouldProcess($g.Name, "Create $($g.Scope) security group")) {
        New-ADGroup -Name $g.Name -SamAccountName $g.Name -GroupScope $g.Scope -GroupCategory Security -Path $g.OuDn -Description $g.Description @adParams
        Write-Step 'Group' $g.Name 'created'
    }
}

# 3. Staff accounts ----------------------------------------------------------
foreach ($u in $plan.Users) {
    $attrs = @{
        GivenName         = $u.GivenName
        Surname           = $u.Surname
        DisplayName       = $u.DisplayName
        UserPrincipalName = $u.UserPrincipalName
        EmailAddress      = $u.EmailAddress
        EmployeeID        = $u.EmployeeID
        Department        = $u.Department
        Title             = $u.Title
        Company           = $u.Company
        Office            = $u.Office
    }
    $existing = Get-ADUser -Filter "SamAccountName -eq '$($u.SamAccountName)'" -Properties DisplayName, EmailAddress, EmployeeID, Department, Title, Company, Office @adParams
    if (-not $existing) {
        if ($PSCmdlet.ShouldProcess($u.SamAccountName, "Create user in $($u.OuPath)")) {
            New-ADUser -Name $u.DisplayName -SamAccountName $u.SamAccountName -Path $u.OuDn -AccountPassword $InitialPassword `
                -ChangePasswordAtLogon $true -Enabled $true @attrs @adParams
            Write-Step 'User' $u.SamAccountName 'created'
        }
        continue
    }
    $diff = @($attrs.Keys | Where-Object { [string]$existing.$_ -ne [string]$attrs[$_] })
    if ($diff.Count -gt 0 -and $PSCmdlet.ShouldProcess($u.SamAccountName, "Update $($diff -join ', ')")) {
        $changes = @{}
        foreach ($k in $diff) { $changes[$k] = $attrs[$k] }
        Set-ADUser -Identity $existing.DistinguishedName @changes @adParams
        Write-Step 'User' $u.SamAccountName "updated ($($diff -join ', '))"
    }
    if ((Get-ParentDn $existing.DistinguishedName) -ne $u.OuDn -and $PSCmdlet.ShouldProcess($u.SamAccountName, "Move to $($u.OuPath)")) {
        Move-ADObject -Identity $existing.DistinguishedName -TargetPath $u.OuDn @adParams
        Write-Step 'User' $u.SamAccountName "updated (moved to $($u.OuPath))"
    }
    elseif ($diff.Count -eq 0) { Write-Step 'User' $u.SamAccountName 'exists' }
}

# 4. Managers ----------------------------------------------------------------
foreach ($u in $plan.Users | Where-Object Manager) {
    $user = Get-ADUser -Filter "SamAccountName -eq '$($u.SamAccountName)'" -Properties Manager @adParams
    $manager = Get-ADUser -Filter "SamAccountName -eq '$($u.Manager)'" @adParams
    if (-not $user -or -not $manager) { continue }   # only possible under -WhatIf
    if ($user.Manager -ne $manager.DistinguishedName -and $PSCmdlet.ShouldProcess($u.SamAccountName, "Set manager $($u.Manager)")) {
        Set-ADUser -Identity $user.DistinguishedName -Manager $manager.DistinguishedName @adParams
        Write-Step 'Manager' $u.SamAccountName "updated ($($u.Manager))"
    }
}

# 5. Privileged accounts -----------------------------------------------------
foreach ($a in $plan.AdminAccounts) {
    $existing = Get-ADUser -Filter "SamAccountName -eq '$($a.SamAccountName)'" -Properties AccountNotDelegated @adParams
    if (-not $existing) {
        if ($PSCmdlet.ShouldProcess($a.SamAccountName, 'Create privileged account')) {
            New-ADUser -Name $a.DisplayName -SamAccountName $a.SamAccountName -UserPrincipalName $a.UserPrincipalName `
                -DisplayName $a.DisplayName -Description $a.Description -Path $a.OuDn -AccountPassword $InitialPassword `
                -ChangePasswordAtLogon $true -Enabled $true -AccountNotDelegated $true @adParams
            Write-Step 'Admin' $a.SamAccountName 'created'
        }
    }
    elseif (-not $existing.AccountNotDelegated -and $PSCmdlet.ShouldProcess($a.SamAccountName, 'Set "account is sensitive and cannot be delegated"')) {
        Set-ADUser -Identity $existing.DistinguishedName -AccountNotDelegated $true @adParams
        Write-Step 'Admin' $a.SamAccountName 'updated (not delegable)'
    }
    else { Write-Step 'Admin' $a.SamAccountName 'exists' }

    foreach ($b in $a.BuiltInGroups) {
        $current = @(Get-ADGroupMember -Identity $b @adParams | ForEach-Object { $_.SamAccountName })
        if ($a.SamAccountName -notin $current -and $PSCmdlet.ShouldProcess($b, "Add $($a.SamAccountName)")) {
            Add-ADGroupMember -Identity $b -Members $a.SamAccountName @adParams
            Write-Step 'Membership' "$b" "added $($a.SamAccountName)"
        }
    }
}

# 6. Memberships -------------------------------------------------------------
foreach ($g in $plan.Groups) {
    if (-not (Get-ADGroup -Filter "Name -eq '$($g.Name)'" @adParams)) { continue }   # -WhatIf run
    $current = @(Get-ADGroupMember -Identity $g.Name @adParams | ForEach-Object { $_.SamAccountName })
    foreach ($m in $g.Members) {
        if ($m -in $current) { continue }
        if ($PSCmdlet.ShouldProcess($g.Name, "Add member $m")) {
            Add-ADGroupMember -Identity $g.Name -Members $m @adParams
            Write-Step 'Membership' $g.Name "added $m"
        }
    }
    foreach ($extra in $current | Where-Object { $_ -notin $g.Members }) {
        if ($RemoveUnexpectedMembers) {
            if ($PSCmdlet.ShouldProcess($g.Name, "Remove unexpected member $extra")) {
                Remove-ADGroupMember -Identity $g.Name -Members $extra -Confirm:$false @adParams
                Write-Step 'Membership' $g.Name "removed $extra"
            }
        }
        else { Write-Step 'Membership' $g.Name "WARN unexpected member $extra (use -RemoveUnexpectedMembers)" }
    }
}

# 7. Delegation (dsacls) -----------------------------------------------------
$usersOu = ($plan.OUs | Where-Object Path -eq 'TechCorp/Users').DistinguishedName
$wksOu = ($plan.OUs | Where-Object Path -eq 'TechCorp/Computers/Workstations').DistinguishedName
$delegations = @(
    @{ Ou = $usersOu; Inherit = '/I:S'; Grant = "$netbios\GG_IT_HelpdeskOperators:CA;Reset Password;user"; What = 'Helpdesk: reset password' }
    @{ Ou = $usersOu; Inherit = '/I:S'; Grant = "$netbios\GG_IT_HelpdeskOperators:RPWP;pwdLastSet;user"; What = 'Helpdesk: must change password at next logon' }
    @{ Ou = $usersOu; Inherit = '/I:S'; Grant = "$netbios\GG_IT_HelpdeskOperators:RPWP;lockoutTime;user"; What = 'Helpdesk: unlock account' }
    @{ Ou = $wksOu; Inherit = '/I:T'; Grant = "$netbios\GG_IT_WorkstationAdmins:CCDC;computer"; What = 'Workstation admins: create/delete computer objects' }
)
foreach ($d in $delegations) {
    if ($PSCmdlet.ShouldProcess($d.Ou, $d.What)) {
        $out = & dsacls.exe $d.Ou $d.Inherit /G $d.Grant 2>&1
        if ($LASTEXITCODE -ne 0) { throw "dsacls failed for '$($d.What)': $out" }
        Write-Step 'Delegation' $d.What 'updated'
    }
}

# 8. Fine-grained password policy for privileged accounts --------------------
$psoName = 'PSO-AdminAccounts'
if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$psoName'" @adParams)) {
    if ($PSCmdlet.ShouldProcess($psoName, 'Create fine-grained password policy')) {
        New-ADFineGrainedPasswordPolicy -Name $psoName -Precedence 10 -MinPasswordLength 20 -ComplexityEnabled $true `
            -PasswordHistoryCount 24 -MinPasswordAge '1.00:00:00' -MaxPasswordAge '365.00:00:00' `
            -LockoutThreshold 5 -LockoutDuration '00:30:00' -LockoutObservationWindow '00:30:00' `
            -ReversibleEncryptionEnabled $false -ProtectedFromAccidentalDeletion $true @adParams
        Write-Step 'PSO' $psoName 'created'
    }
}
else { Write-Step 'PSO' $psoName 'exists' }
$subjects = @()
try { $subjects = @(Get-ADFineGrainedPasswordPolicySubject -Identity $psoName @adParams | ForEach-Object { $_.Name }) }
catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] { $subjects = @() }   # PSO not created yet (-WhatIf)
if ('GG_IT_AdminAccounts' -notin $subjects -and $PSCmdlet.ShouldProcess($psoName, 'Apply to GG_IT_AdminAccounts')) {
    Add-ADFineGrainedPasswordPolicySubject -Identity $psoName -Subjects 'GG_IT_AdminAccounts' @adParams
    Write-Step 'PSO' $psoName 'updated (applied to GG_IT_AdminAccounts)'
}

# 9. Machine account quota ---------------------------------------------------
$maq = (Get-ADObject -Identity $domain.DistinguishedName -Properties 'ms-DS-MachineAccountQuota' @adParams).'ms-DS-MachineAccountQuota'
if ($maq -ne 0 -and $PSCmdlet.ShouldProcess($domain.DNSRoot, "Set ms-DS-MachineAccountQuota from $maq to 0")) {
    Set-ADDomain -Identity $domain.DistinguishedName -Replace @{ 'ms-DS-MachineAccountQuota' = 0 } @adParams
    Write-Step 'Domain' 'ms-DS-MachineAccountQuota' 'updated (0)'
}

# Report ---------------------------------------------------------------------
$summary = $script:Log | Group-Object { ($_.Result -split ' ')[0] } | ForEach-Object { "$($_.Name)=$($_.Count)" }
Write-Host ("Done: " + ($summary -join ', '))
if ($ReportPath) {
    $script:Log | Export-Csv -LiteralPath $ReportPath -NoTypeInformation -Encoding UTF8
    Write-Host "Report written to $ReportPath"
}
