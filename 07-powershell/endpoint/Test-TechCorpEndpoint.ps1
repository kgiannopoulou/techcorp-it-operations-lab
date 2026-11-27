<#
.SYNOPSIS
    Checks a TechCorp laptop against the workstation standard and prints
    PASS / FAIL / SKIP per check. Read-only - run it at the end of every build
    and whenever a laptop "behaves strangely".

.DESCRIPTION
    Checks (DEP-STD-001 workstation standard, END-PRC-001 build procedure):
      Identity  - hostname = asset tag in hardware-inventory.csv, Windows 11
                  Pro/Enterprise, domain joined, hybrid Entra joined, PRT present
      Security  - TPM ready, Secure Boot, BitLocker on C: (XTS-AES 256, protection
                  on, recovery password protector), Defender real-time protection,
                  firewall on for all profiles, no unexpected local administrators,
                  Windows LAPS policy present
      Policy    - expected computer GPOs applied (gpresult)
      Time      - clock within 60 s of the domain
      Software  - every winget / capability app from the baseline for the owner

    Hybrid join and PRT come from 'dsregcmd /status'. The PRT check only makes
    sense in a signed-in user session (run without elevation for that row).

.PARAMETER Username
    Laptop owner - used to work out the expected software. Defaults to the
    AssignedTo value of this computer in hardware-inventory.csv.

.PARAMETER OutputPath
    Optional CSV path for the results (evidence for the build ticket).

.EXAMPLE
    .\Test-TechCorpEndpoint.ps1

.EXAMPLE
    .\Test-TechCorpEndpoint.ps1 -OutputPath "$env:PUBLIC\Desktop\$env:COMPUTERNAME-build.csv"
#>
[CmdletBinding()]
param(
    [string]$Username,

    [string]$OutputPath,

    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:Results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$Area, [string]$Check, [string]$Status, [string]$Detail = '') {
    $script:Results.Add([pscustomobject]@{ Area = $Area; Check = $Check; Status = $Status; Detail = $Detail })
}
function Test-Check([string]$Area, [string]$Check, [bool]$Condition, [string]$Detail = '') {
    Add-Result $Area $Check $(if ($Condition) { 'PASS' } else { 'FAIL' }) $Detail
}
function Invoke-Safely([scriptblock]$Block) {
    try { return & $Block } catch { return $null }
}

$inventory = @(Import-Csv -LiteralPath (Join-Path $Root '01-office-deployment/equipment-inventory/hardware-inventory.csv') -Encoding UTF8)
$asset = @($inventory | Where-Object Hostname -eq $env:COMPUTERNAME)

# Identity -------------------------------------------------------------------
Test-Check 'Identity' 'Hostname is a registered asset' ($asset.Count -eq 1) $env:COMPUTERNAME
if (-not $Username -and $asset.Count -eq 1 -and $asset[0].AssignedTo -notin '', 'Spare', 'Shared') { $Username = $asset[0].AssignedTo }

$os = Get-CimInstance -ClassName Win32_OperatingSystem
Test-Check 'Identity' 'Windows 11 Pro / Enterprise' ($os.Caption -match 'Windows 11 (Pro|Enterprise)') "$($os.Caption) build $($os.BuildNumber)"
$cs = Get-CimInstance -ClassName Win32_ComputerSystem
Test-Check 'Identity' 'Joined to corp.techcorp.example' ($cs.PartOfDomain -and $cs.Domain -eq 'corp.techcorp.example') $cs.Domain

$dsreg = @{}
foreach ($line in (& dsregcmd.exe /status)) {
    if ($line -match '^\s*([A-Za-z]+)\s*:\s*(.+?)\s*$') { $dsreg[$Matches[1]] = $Matches[2] }
}
Test-Check 'Identity' 'Hybrid Entra joined (AzureAdJoined + DomainJoined)' ($dsreg['AzureAdJoined'] -eq 'YES' -and $dsreg['DomainJoined'] -eq 'YES') "AzureAdJoined=$($dsreg['AzureAdJoined'])"
if ($dsreg.ContainsKey('AzureAdPrt')) {
    Test-Check 'Identity' 'Primary Refresh Token (SSO to Microsoft 365)' ($dsreg['AzureAdPrt'] -eq 'YES') 'run in the user session'
}
else { Add-Result 'Identity' 'Primary Refresh Token' 'SKIP' 'no user state in this session' }

# Security -------------------------------------------------------------------
$tpm = Invoke-Safely { Get-Tpm }
Test-Check 'Security' 'TPM present and ready' ($tpm -and $tpm.TpmPresent -and $tpm.TpmReady)
$sb = Invoke-Safely { Confirm-SecureBootUEFI }
Test-Check 'Security' 'Secure Boot on' ($sb -eq $true)

$bl = Invoke-Safely { Get-BitLockerVolume -MountPoint 'C:' }
if ($bl) {
    $protectors = @($bl.KeyProtector | ForEach-Object { [string]$_.KeyProtectorType })
    Test-Check 'Security' 'BitLocker C: fully encrypted, protection on' ($bl.VolumeStatus -eq 'FullyEncrypted' -and [string]$bl.ProtectionStatus -eq 'On') "$($bl.VolumeStatus), $($bl.ProtectionStatus)"
    Test-Check 'Security' 'BitLocker XTS-AES 256' ([string]$bl.EncryptionMethod -eq 'XtsAes256') ([string]$bl.EncryptionMethod)
    Test-Check 'Security' 'BitLocker TPM + recovery password protectors' (('Tpm' -in $protectors) -and ('RecoveryPassword' -in $protectors)) ($protectors -join ', ')
}
else { Add-Result 'Security' 'BitLocker' 'FAIL' 'Get-BitLockerVolume failed - run elevated' }

$mp = Invoke-Safely { Get-MpComputerStatus }
Test-Check 'Security' 'Defender real-time protection on' ($mp -and $mp.RealTimeProtectionEnabled) $(if ($mp) { "signatures $($mp.AntivirusSignatureLastUpdated)" } else { 'not available' })
foreach ($p in Get-NetFirewallProfile) { Test-Check 'Security' "Firewall $($p.Name) profile on" ([bool]$p.Enabled) }

$admins = @(Invoke-Safely { Get-LocalGroupMember -SID 'S-1-5-32-544' } | ForEach-Object { $_.Name })
$unexpected = @($admins | Where-Object { $_ -notlike '*\Administrator' -and $_ -notlike '*\GG_IT_WorkstationAdmins' -and $_ -notlike '*\Domain Admins' })
Test-Check 'Security' 'Local Administrators = Administrator + GG_IT_WorkstationAdmins only' ($admins.Count -gt 0 -and $unexpected.Count -eq 0) $(if ($unexpected) { "unexpected: $($unexpected -join ', ')" } else { $admins -join ', ' })
$laps = Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\LAPS' -ErrorAction SilentlyContinue
Test-Check 'Security' 'Windows LAPS policy (backup to AD)' ($laps -and $laps.PSObject.Properties['BackupDirectory'] -and $laps.BackupDirectory -eq 2)

# Policy ---------------------------------------------------------------------
$gp = (& gpresult.exe /r /scope computer 2>$null) -join "`n"
foreach ($name in 'C-AllComputers-SecurityBaseline', 'C-Workstations-LAPS', 'C-Workstations-BitLocker', 'C-Workstations-OneDrive') {
    Test-Check 'Policy' "GPO applied: $name" ($gp -match [regex]::Escape($name))
}

# Time -----------------------------------------------------------------------
$skew = (& w32tm.exe /stripchart /computer:corp.techcorp.example /samples:1 /dataonly 2>$null) | Select-Object -Last 1
if ($skew -match ',\s*([+-]?\d+(\.\d+)?)s') { Test-Check 'Time' 'Clock within 60 s of the domain' ([math]::Abs([double]$Matches[1]) -lt 60) "$($Matches[1]) s" }
else { Add-Result 'Time' 'Clock skew' 'SKIP' 'domain not reachable' }

# Software -------------------------------------------------------------------
if ($Username) {
    $apps = & (Join-Path $PSScriptRoot 'Install-TechCorpBaseline.ps1') -Username $Username -ListOnly -Root $Root 6>$null
    foreach ($a in $apps) {
        switch ($a.Method) {
            'winget' {
                $null = & winget.exe list --id $a.Id --exact --accept-source-agreements --disable-interactivity 2>&1
                Test-Check 'Software' $a.App ($LASTEXITCODE -eq 0) $a.Id
            }
            'capability' { Test-Check 'Software' $a.App ((Invoke-Safely { (Get-WindowsCapability -Online -Name $a.Id).State }) -eq 'Installed') }
            'odt' {
                $c2r = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
                Test-Check 'Software' $a.App ($c2r -and $c2r.PSObject.Properties['ProductReleaseIds'] -and $c2r.ProductReleaseIds -like '*O365BusinessRetail*')
            }
            default { Add-Result 'Software' $a.App 'SKIP' "$($a.Method) - check by hand" }
        }
    }
}
else { Add-Result 'Software' 'Baseline apps' 'SKIP' 'spare laptop - pass -Username' }

# Output ---------------------------------------------------------------------
$script:Results | Format-Table -AutoSize -Wrap
Write-Host (($script:Results | Group-Object Status | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ' | ')
if ($OutputPath) {
    $script:Results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "Results written to $OutputPath"
}
if (@($script:Results | Where-Object Status -eq 'FAIL').Count -gt 0) { exit 1 }
exit 0
