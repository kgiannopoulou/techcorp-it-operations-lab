<#
.SYNOPSIS
    Runs the Pester test suite for the PowerShell scripts (07-powershell/tests).

.DESCRIPTION
    Needs Pester 5 (preinstalled in PowerShell 7 on GitHub's runners; on a
    Windows PC: Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser
    -SkipPublisherCheck - Windows ships the old Pester 3.4, which cannot run
    these tests).

    Writes NUnit XML to -ResultPath so CI keeps the result as evidence.
    Exit code = number of failed tests (0 = all passed).

.EXAMPLE
    ./07-powershell/tests/Invoke-TechCorpTests.ps1

.EXAMPLE
    ./07-powershell/tests/Invoke-TechCorpTests.ps1 -Path ./07-powershell/tests/TechCorp.Admin.Tests.ps1 -Output Detailed
#>
[CmdletBinding()]
param(
    [string[]]$Path = @($PSScriptRoot),
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')][string]$Output = 'Normal',
    [string]$ResultPath = (Join-Path (Get-Location) 'output/test-results.xml')
)

$ErrorActionPreference = 'Stop'
$pester = Get-Module -ListAvailable Pester | Where-Object { $_.Version -ge [version]'5.0.0' } | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester) {
    throw 'Pester 5 is required: Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -SkipPublisherCheck'
}
Import-Module $pester -Force

$dir = Split-Path -Parent $ResultPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$config = New-PesterConfiguration
$config.Run.Path = $Path
$config.Run.PassThru = $true
$config.Output.Verbosity = $Output
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
$config.TestResult.OutputPath = $ResultPath

$result = Invoke-Pester -Configuration $config
Write-Host ("Pester {0}: {1} passed, {2} failed, {3} skipped -> {4}" -f $pester.Version, $result.PassedCount, $result.FailedCount, $result.SkippedCount, $ResultPath)
exit $result.FailedCount
