<#
.SYNOPSIS
    Deletes files older than a retention period from log, temp and export
    folders - with -WhatIf, a size summary, a log, and refusal to touch
    system or profile roots.

.DESCRIPTION
    Typical uses at TechCorp (scheduled weekly, maintenance calendar):
      - the daily-check reports on TC-FS01, D:\Shares\IT\Reports (share IT$) - keep 90 days
      - the scripts' own output\logs folders - keep 90 days
      - application logs on the servers (e.g. Entra Connect traces on TC-SYNC01)
    Retention follows BR-18 (logs kept at least 90 days) - never set lower for logs.

    Safety rails:
      - refuses drive roots, the Windows and Program Files folders, user
        profile roots and the repository itself;
      - only files are deleted (never folders, unless -RemoveEmptyFolders);
      - -Include narrows the match (default *.log, *.tmp, *.csv, *.html,
        *.txt); use '*' deliberately;
      - asks once more above -ConfirmAbove files (500) unless -Force -
        scheduled tasks pass -Force -Confirm:$false.

    Selection is Get-TcOldFile (unit tested); every deletion supports -WhatIf.

.EXAMPLE
    .\Remove-TechCorpOldFile.ps1 -Path .\output\reports -OlderThanDays 90 -WhatIf

.EXAMPLE
    .\Remove-TechCorpOldFile.ps1 -Path D:\Shares\IT\Reports -OlderThanDays 90 -Recurse -Force -Confirm:$false
    As the weekly scheduled task runs it.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][string[]]$Path,
    [Parameter(Mandatory)][ValidateRange(1, 3650)][int]$OlderThanDays,
    [string[]]$Include = @('*.log', '*.tmp', '*.csv', '*.html', '*.txt'),
    [switch]$Recurse,
    [switch]$RemoveEmptyFolders,
    [int]$ConfirmAbove = 500,
    [switch]$Force,
    [string]$LogPath = (Join-Path (Get-Location) 'output/logs/Remove-TechCorpOldFile.log'),
    [datetime]$Now = (Get-Date)
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../modules/TechCorp.Admin/TechCorp.Admin.psd1') -Force

function ConvertTo-FullPath([string]$Value) { ([IO.Path]::GetFullPath($Value)).TrimEnd('\', '/') }

# exact folders that are never cleaned (a profile root, the repository)
$protected = New-Object System.Collections.Generic.List[string]
foreach ($p in @($env:USERPROFILE, $HOME, (Split-Path -Parent $HOME))) { if ($p) { $protected.Add((ConvertTo-FullPath $p)) } }
try { $protected.Add((Get-TcRepoRoot -StartPath $PSScriptRoot).TrimEnd('\', '/')) } catch { Write-Verbose 'repository root not found - not protected' }
# trees that are never cleaned, except their Temp and Logs subfolders
$systemTrees = @(foreach ($p in @($env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData)) { if ($p) { ConvertTo-FullPath $p } })

$summary = foreach ($folder in $Path) {
    $candidate = if ([IO.Path]::IsPathRooted($folder)) { $folder } else { Join-Path (Get-Location) $folder }
    $full = ConvertTo-FullPath $candidate
    $isRoot = (-not $full) -or $full -eq ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($candidate))).TrimEnd('\', '/')
    $inSystem = @($systemTrees | Where-Object { $full -eq $_ -or $full.StartsWith("$_\", [StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith("$_/", [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0 -and
        $full -notmatch '[\\/](Temp|Logs)([\\/]|$)'
    if ($isRoot -or $inSystem -or $protected -contains $full) {
        Write-TcLog -Message "refused protected path $full" -Level ERROR -Path $LogPath | Out-Null
        Write-Error "Refusing to clean '$full' - drive root, system, profile or repository folder." -ErrorAction Continue
        [pscustomobject]@{ Path = $full; Files = 0; Deleted = 0; FreedMB = 0; Status = 'Refused' }
        continue
    }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        Write-Warning "Folder not found: $full"
        [pscustomobject]@{ Path = $full; Files = 0; Deleted = 0; FreedMB = 0; Status = 'NotFound' }
        continue
    }

    $files = @(Get-TcOldFile -Path $full -OlderThanDays $OlderThanDays -Include $Include -Recurse:$Recurse -Now $Now)
    $bytes = [int64]0
    foreach ($f in $files) { $bytes += $f.Length }
    $confirmAll = $Force -or $WhatIfPreference -or $files.Count -le $ConfirmAbove -or $PSCmdlet.ShouldContinue("$($files.Count) files ($([math]::Round($bytes / 1MB, 1)) MB) in $full", 'Delete old files?')
    $deleted = 0; $freed = [int64]0; $failed = 0
    if ($confirmAll) {
        foreach ($f in $files) {
            if ($PSCmdlet.ShouldProcess($f.FullName, "Delete (last written $($f.LastWriteTime.ToString('yyyy-MM-dd')))")) {
                try {
                    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                    $deleted++; $freed += $f.Length
                }
                catch { $failed++; Write-TcLog -Message "could not delete $($f.FullName): $($_.Exception.Message)" -Level WARN -Path $LogPath | Out-Null }
            }
        }
        if ($RemoveEmptyFolders -and $Recurse) {
            Get-ChildItem -LiteralPath $full -Directory -Recurse -Force | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
                if (@(Get-ChildItem -LiteralPath $_.FullName -Force).Count -eq 0 -and $PSCmdlet.ShouldProcess($_.FullName, 'Remove empty folder')) {
                    Remove-Item -LiteralPath $_.FullName -Force
                }
            }
        }
    }
    $status = if (-not $confirmAll) { 'Cancelled' } elseif ($failed) { 'Partial' } elseif ($WhatIfPreference) { 'WhatIf' } else { 'Done' }
    if (-not $WhatIfPreference) {
        Write-TcLog -Message ("{0}: {1} of {2} file(s) older than {3} days deleted, {4:N1} MB freed, {5} failed" -f $full, $deleted, $files.Count, $OlderThanDays, ($freed / 1MB), $failed) -Level CHANGE -Path $LogPath | Out-Null
    }
    [pscustomobject]@{ Path = $full; Files = $files.Count; Deleted = $deleted; FreedMB = [math]::Round($freed / 1MB, 2); Status = $status }
}

$summary
if (@($summary | Where-Object { $_.Status -in 'Refused', 'Partial' }).Count -gt 0) { exit 1 }
exit 0
