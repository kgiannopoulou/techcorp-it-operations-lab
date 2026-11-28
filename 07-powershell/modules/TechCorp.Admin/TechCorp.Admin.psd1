@{
    RootModule        = 'TechCorp.Admin.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '5d0c7a8e-3f8b-4a51-9d0e-6b1f2c4e7a19'
    Author            = 'TechCorp IT'
    CompanyName       = 'TechCorp (fictional)'
    Copyright         = '(c) TechCorp IT Operations Lab. MIT licence.'
    Description       = 'Shared, unit-tested helpers for the TechCorp administrative scripts (Milestone 8).'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @(
        'Get-TcRepoRoot', 'Import-TcData', 'ConvertTo-TcOuDn',
        'Write-TcLog', 'New-TcResult', 'Get-TcOverallStatus', 'Get-TcExitCode',
        'ConvertTo-TcAsciiName', 'Get-TcUsername', 'Get-TcRandomPassword',
        'Get-TcPasswordExpiry', 'Get-TcStaleAccount', 'Get-TcWarrantyStatus',
        'Get-TcDiskStatus', 'Get-TcOldFile', 'Test-TcTcpPort', 'ConvertFrom-TcStripchart', 'Get-TcPasswordExpiryMessage',
        'ConvertTo-TcHtmlReport', 'ConvertTo-TcBool', 'ConvertTo-TcDate'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{ Tags = @('TechCorp', 'ActiveDirectory', 'Administration') } }
}
