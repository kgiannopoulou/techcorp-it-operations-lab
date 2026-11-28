#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# The rules in 07-powershell/README.md "Script standards", enforced for every script.

BeforeDiscovery {
    $ps = Join-Path $PSScriptRoot '..'
    $scripts = @(Get-ChildItem -Path $ps -Recurse -Filter '*.ps1' | Where-Object { $_.FullName -notmatch '[\\/]tests[\\/]' } |
        ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
    $changeVerbs = 'Deploy', 'Disable', 'Install', 'New', 'Remove', 'Send', 'Set'
    $changing = @($scripts | Where-Object { $_.Name.Split('-')[0] -in $changeVerbs })
    $allFiles = @(Get-ChildItem -Path $ps -Recurse -Include '*.ps1', '*.psm1', '*.psd1' | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
}

Describe 'Script <Name>' -ForEach $scripts {
    BeforeAll {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        $help = $ast.GetHelpContent()
    }
    It 'parses without errors' { $errors.Count | Should -Be 0 }
    It 'has comment-based help with a synopsis, a description and an example' {
        $help | Should -Not -BeNullOrEmpty
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description | Should -Not -BeNullOrEmpty
        $help.Examples.Count | Should -BeGreaterThan 0
    }
    It 'uses [CmdletBinding()]' {
        @($ast.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' }).Count | Should -Be 1
    }
    It 'has no hard-coded password or secret' {
        $raw = Get-Content -LiteralPath $Path -Raw
        $raw | Should -Not -Match '(?i)(password|secret|apikey|token)\s*=\s*[''"][^''"\s$]{4,}'
        $raw | Should -Not -Match '(?i)ConvertTo-SecureString\s+.*-AsPlainText'
    }
}

Describe 'State-changing script <Name>' -ForEach $changing {
    It 'supports -WhatIf / -Confirm' {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        $binding = @($ast.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' })[0]
        $binding.Extent.Text | Should -Match 'SupportsShouldProcess'
    }
}

Describe 'File <Name>' -ForEach $allFiles {
    It 'is plain ASCII (Windows PowerShell 5.1 reads BOM-less files as ANSI)' {
        [IO.File]::ReadAllText($Path) | Should -MatchExactly '^[\x00-\x7F]*$'
    }
}

Describe 'TechCorp.Admin module' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '../modules/TechCorp.Admin/TechCorp.Admin.psd1') -Force
        $manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot '../modules/TechCorp.Admin/TechCorp.Admin.psd1')
    }
    It 'exports exactly the functions listed in the manifest' {
        @((Get-Command -Module TechCorp.Admin).Name | Sort-Object) | Should -Be @($manifest.FunctionsToExport | Sort-Object)
    }
    It 'documents every exported function' {
        foreach ($f in $manifest.FunctionsToExport) {
            (Get-Help $f).Synopsis | Should -Not -Match "^\s*$f" -Because "$f needs a .SYNOPSIS"
        }
    }
}
