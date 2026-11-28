<#
.SYNOPSIS
    The IT specialist's 08:30 check in one run: server health, service ports,
    stale accounts and password expiry -> one HTML report and an exit code.

.DESCRIPTION
    Runs the Milestone 8 scripts in sequence and collects their result rows:

      1. Get-TechCorpServerHealth.ps1    servers with role services in data/server-roles.csv
      2. Test-TechCorpServicePort.ps1    every host in data/server-roles.csv
      3. Get-TechCorpStaleAccountReport.ps1  (needs the ActiveDirectory module)
      4. Send-TechCorpPasswordExpiryNotice.ps1  report only, or sends with -SmtpServer

    Steps 3-4 are SKIPped with a reason when the ActiveDirectory module is
    missing, so the check also runs on a PC without RSAT. One failing step
    never stops the others.

    Writes daily-check-<date>.html (plus every step's own CSV) to
    -OutputFolder. With -MailTo and -SmtpServer the HTML is e-mailed.
    Exit code: 0 all PASS, 1 any WARN, 2 any FAIL.

    Scheduled task (on TC-FS01, as a gMSA - no stored password; Phase 10):

        $action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy RemoteSigned -File D:\Shares\IT\Scripts\07-powershell\maintenance\Invoke-TechCorpDailyCheck.ps1 -OutputFolder D:\Shares\IT\Reports\daily'
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday, Tuesday, Wednesday, Thursday, Friday -At 08:00
        $principal = New-ScheduledTaskPrincipal -UserId 'CORP\gmsa-itops$' -LogonType Password
        Register-ScheduledTask -TaskName 'TechCorp daily check' -Action $action -Trigger $trigger -Principal $principal

.EXAMPLE
    .\Invoke-TechCorpDailyCheck.ps1 -ComputerName $env:COMPUTERNAME -SkipPorts
    Local run on any PC.

.EXAMPLE
    .\Invoke-TechCorpDailyCheck.ps1 -TimeSource TC-DC01 -SmtpServer techcorp-example.mail.protection.outlook.com -MailTo it@techcorp.example
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$ComputerName,
    [string]$TimeSource,
    [switch]$SkipPorts,
    [switch]$SkipAd,
    [string]$SmtpServer,
    [string]$MailTo,
    [string]$From = 'it-noreply@techcorp.example',
    [string]$Root,
    [string]$OutputFolder = (Join-Path (Get-Location) 'output/reports'),
    [datetime]$Now = (Get-Date)
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../modules/TechCorp.Admin/TechCorp.Admin.psd1') -Force
if (-not $Root) { $Root = Get-TcRepoRoot -StartPath $PSScriptRoot }
$ps = Join-Path $Root '07-powershell'
if (-not $ComputerName) { $ComputerName = @(Import-TcData server-roles -Root $Root | Where-Object Services | ForEach-Object Hostname) }

$sections = [ordered]@{}
$all = New-Object System.Collections.Generic.List[object]

function Invoke-Step([string]$Name, [scriptblock]$Run) {
    $rows = @()
    try { $rows = @(& $Run | Where-Object { $_ -and $_.PSObject.Properties['Status'] }) }
    catch { $rows = @(New-TcResult -Check $Name -Target 'step' -Status FAIL -Detail "step failed: $($_.Exception.Message)") }
    if ($rows.Count -eq 0) { $rows = @(New-TcResult -Check $Name -Target 'step' -Status PASS -Detail 'nothing to report') }
    $sections[$Name] = $rows
    foreach ($r in $rows) { $all.Add($r) }
}

$healthParams = @{ ComputerName = $ComputerName; Root = $Root; OutputFolder = $OutputFolder; Now = $Now }
if ($TimeSource) { $healthParams.TimeSource = $TimeSource }
Invoke-Step 'Server health' {
    & (Join-Path $ps 'maintenance/Get-TechCorpServerHealth.ps1') @healthParams 6>$null
}
if ($SkipPorts) { $sections['Service ports'] = @(New-TcResult -Check 'Service ports' -Target 'step' -Status SKIP -Detail '-SkipPorts') }
else {
    Invoke-Step 'Service ports' { & (Join-Path $ps 'network-diagnostics/Test-TechCorpServicePort.ps1') -Root $Root -OutputPath (Join-Path $OutputFolder "service-ports-$($Now.ToString('yyyy-MM-dd')).csv") 6>$null }
}

$adAvailable = -not $SkipAd -and [bool](Get-Module -ListAvailable ActiveDirectory)
if ($adAvailable) {
    Invoke-Step 'Stale accounts' {
        & (Join-Path $ps 'reporting/Get-TechCorpStaleAccountReport.ps1') -OutputFolder $OutputFolder -Now $Now 6>$null |
            ForEach-Object { New-TcResult -Check "Stale $($_.Type.ToLower())" -Target $_.Name -Status WARN -Detail $_.Findings }
    }
    Invoke-Step 'Password expiry' {
        $expiryParams = @{ OutputFolder = $OutputFolder; Now = $Now }
        if ($SmtpServer) { $expiryParams.SmtpServer = $SmtpServer; $expiryParams.From = $From }
        & (Join-Path $ps 'reporting/Send-TechCorpPasswordExpiryNotice.ps1') @expiryParams 6>$null |
            ForEach-Object {
                $s = if ($_.State -eq 'Expired') { 'FAIL' } else { 'WARN' }
                New-TcResult -Check 'Password expiry' -Target $_.SamAccountName -Status $s -Detail "$($_.State), $($_.DaysLeft) day(s), reminder: $($_.Sent)"
            }
    }
}
else {
    $why = if ($SkipAd) { '-SkipAd' } else { 'ActiveDirectory module not installed (RSAT)' }
    foreach ($n in 'Stale accounts', 'Password expiry') { $sections[$n] = @(New-TcResult -Check $n -Target 'step' -Status SKIP -Detail $why) }
}

$overall = Get-TcOverallStatus -Result $all.ToArray()
$summary = @(foreach ($k in $sections.Keys) {
    $rows = @($sections[$k])
    [pscustomobject]@{
        Step   = $k
        Status = Get-TcOverallStatus -Result $rows
        PASS   = @($rows | Where-Object Status -eq 'PASS').Count
        WARN   = @($rows | Where-Object Status -eq 'WARN').Count
        FAIL   = @($rows | Where-Object Status -eq 'FAIL').Count
    }
})
$report = [ordered]@{ 'Summary' = $summary }
foreach ($k in $sections.Keys) {
    # only what needs attention in the detail tables; the CSVs keep everything
    $report[$k] = @($sections[$k] | Where-Object { $_.Status -ne 'PASS' })
}

if (-not (Test-Path -LiteralPath $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force -WhatIf:$false | Out-Null }
$html = Join-Path $OutputFolder "daily-check-$($Now.ToString('yyyy-MM-dd')).html"
$title = "TechCorp daily check $($Now.ToString('yyyy-MM-dd')) - $overall"
ConvertTo-TcHtmlReport -Title $title -Section $report -Now $Now | Set-Content -LiteralPath $html -Encoding UTF8 -WhatIf:$false
Write-Host "Daily check: $overall ($($all.Count) checks) -> $html"

if ($MailTo -and $SmtpServer -and $PSCmdlet.ShouldProcess($MailTo, "E-mail '$title'")) {
    $mail = New-Object System.Net.Mail.MailMessage($From, $MailTo, $title, (Get-Content -LiteralPath $html -Raw -Encoding UTF8))
    $mail.IsBodyHtml = $true
    $client = New-Object System.Net.Mail.SmtpClient($SmtpServer, 25)
    try { $client.Send($mail) } finally { $mail.Dispose(); $client.Dispose() }
}

$summary
exit (Get-TcExitCode -Result $all.ToArray())
