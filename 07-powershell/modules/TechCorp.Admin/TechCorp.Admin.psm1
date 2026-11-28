#Requires -Version 5.1
<#
    TechCorp.Admin - shared helpers for the Milestone 8 administrative scripts.

    Every function here is "pure" where it can be: it takes objects in and
    returns objects out, with the current time passed as -Now, so it can be
    unit tested with Pester without Active Directory, a mail server or a
    particular day of the week. The scripts in user-management/, reporting/,
    maintenance/ and network-diagnostics/ do the I/O and call these functions.

    Windows PowerShell 5.1 and PowerShell 7, ASCII only, no credentials.
#>

Set-StrictMode -Version 3.0

# ------------------------------------------------------------------ repository

function Get-TcRepoRoot {
    <#
    .SYNOPSIS
        Returns the repository root (the folder that contains 00-company-overview).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$StartPath = $PSScriptRoot)

    $dir = (Resolve-Path -LiteralPath $StartPath).Path
    while ($dir) {
        if (Test-Path -LiteralPath (Join-Path $dir '00-company-overview')) { return $dir }
        $parent = Split-Path -Parent $dir
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    throw "Repository root not found above '$StartPath'."
}

function Import-TcData {
    <#
    .SYNOPSIS
        Imports one of the repository's source-of-truth CSV files by short name.
    .EXAMPLE
        Import-TcData employees
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('employees', 'inventory', 'departments', 'groups', 'ous', 'server-roles')]
        [string]$Name,

        [string]$Root = (Get-TcRepoRoot)
    )

    $relative = @{
        'employees'     = '00-company-overview/data/employees.csv'
        'inventory'     = '01-office-deployment/equipment-inventory/hardware-inventory.csv'
        'departments'   = '03-windows-server/users-and-groups/department-map.csv'
        'groups'        = '03-windows-server/users-and-groups/ad-groups.csv'
        'ous'           = '03-windows-server/users-and-groups/ou-structure.csv'
        'server-roles'  = '07-powershell/data/server-roles.csv'
    }[$Name]
    $path = Join-Path $Root $relative
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing data file: $relative" }
    return @(Import-Csv -LiteralPath $path -Encoding UTF8)
}

function ConvertTo-TcOuDn {
    <#
    .SYNOPSIS
        Converts a repository OU path (TechCorp/Users/IT) to a distinguished name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$DomainDn = 'DC=corp,DC=techcorp,DC=example'
    )
    $parts = $Path.Split('/')
    [Array]::Reverse($parts)
    return ((@($parts | ForEach-Object { "OU=$_" }) -join ',') + ",$DomainDn")
}

# ------------------------------------------------------------------ logging and results

function Write-TcLog {
    <#
    .SYNOPSIS
        Appends one timestamped line to a log file (and echoes it to the verbose stream).
    .DESCRIPTION
        Line format: 2026-11-28T09:15:02+02:00 [INFO] message
        The folder is created if needed. Never logs secrets - callers pass
        descriptions, not values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'CHANGE')][string]$Level = 'INFO',
        [string]$Path,
        [datetime]$Now = (Get-Date)
    )
    $line = '{0} [{1}] {2}' -f $Now.ToString('yyyy-MM-ddTHH:mm:sszzz'), $Level, $Message
    Write-Verbose $line
    if ($Path) {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
    }
    return $line
}

function New-TcResult {
    <#
    .SYNOPSIS
        Creates one check result row: Check, Target, Status (PASS/WARN/FAIL/SKIP), Detail.
        All verification and report scripts in this repository emit these rows.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an in-memory object only')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Check,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Target,
        [Parameter(Mandatory)][ValidateSet('PASS', 'WARN', 'FAIL', 'SKIP')][string]$Status,
        [AllowEmptyString()][string]$Detail = ''
    )
    [pscustomobject]@{ Check = $Check; Target = $Target; Status = $Status; Detail = $Detail }
}

function Get-TcOverallStatus {
    <#
    .SYNOPSIS
        Worst status of a set of results: FAIL > WARN > PASS. SKIP is ignored;
        no results (or only SKIP) gives SKIP.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Result)

    $statuses = @($Result | ForEach-Object { $_.Status })
    foreach ($s in 'FAIL', 'WARN', 'PASS') { if ($statuses -contains $s) { return $s } }
    return 'SKIP'
}

function Get-TcExitCode {
    <#
    .SYNOPSIS
        Maps results to the exit code every script uses: 0 = PASS/SKIP, 1 = WARN, 2 = FAIL.
        A scheduled task or monitoring agent can alert on a non-zero code.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Result)
    switch (Get-TcOverallStatus -Result $Result) { 'FAIL' { 2 } 'WARN' { 1 } default { 0 } }
}

# ------------------------------------------------------------------ accounts

function ConvertTo-TcAsciiName {
    <#
    .SYNOPSIS
        Lower-case ASCII letters only: removes accents (Zoe from Zo-umlaut-e), spaces,
        apostrophes and hyphens - the characters that break logon names and e-mail.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)

    $decomposed = $Name.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $decomposed.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    # characters that do not decompose into base + accent
    $map = @{ ([char]0x00DF) = 'ss'; ([char]0x00F8) = 'o'; ([char]0x00D8) = 'o'; ([char]0x0142) = 'l'; ([char]0x0141) = 'l'; ([char]0x00E6) = 'ae'; ([char]0x00C6) = 'ae'; ([char]0x0111) = 'd'; ([char]0x0110) = 'd' }
    $folded = New-Object System.Text.StringBuilder
    foreach ($ch in $sb.ToString().ToCharArray()) {
        if ($map.ContainsKey($ch)) { [void]$folded.Append($map[$ch]) } else { [void]$folded.Append($ch) }
    }
    return ($folded.ToString().ToLowerInvariant() -replace '[^a-z]', '')
}

function Get-TcUsername {
    <#
    .SYNOPSIS
        Generates a unique firstname.lastname logon name (naming-conventions.md).
    .DESCRIPTION
        - ASCII-folded and lower case (ConvertTo-TcAsciiName)
        - at most 20 characters (sAMAccountName limit) - the last name is
          shortened, never the first name's initial
        - on a collision a number is appended: eren.yeager2, eren.yeager3 ...
    .EXAMPLE
        Get-TcUsername -FirstName 'Zoe' -LastName "O'Brien-Smith" -Existing (Import-TcData employees).Username
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$FirstName,
        [Parameter(Mandatory)][string]$LastName,
        [AllowEmptyCollection()][string[]]$Existing = @(),
        [ValidateRange(8, 64)][int]$MaxLength = 20
    )

    $first = ConvertTo-TcAsciiName $FirstName
    $last = ConvertTo-TcAsciiName $LastName
    if (-not $first -or -not $last) { throw "Cannot build a logon name from '$FirstName' '$LastName' (no letters left after normalisation)." }

    $taken = @{}
    foreach ($e in $Existing) { if ($e) { $taken[$e.ToLowerInvariant()] = $true } }

    for ($n = 1; $n -le 99; $n++) {
        $suffix = if ($n -eq 1) { '' } else { [string]$n }
        $room = $MaxLength - $suffix.Length
        $candidate = "$first.$last"
        if ($candidate.Length -gt $room) {
            $lastRoom = $room - $first.Length - 1
            if ($lastRoom -ge 1) { $candidate = "$first." + $last.Substring(0, [math]::Min($last.Length, $lastRoom)) }
            else { $candidate = $first.Substring(0, $room - 2) + '.' + $last.Substring(0, 1) }
        }
        $candidate += $suffix
        if (-not $taken.ContainsKey($candidate)) { return $candidate }
    }
    throw "No free logon name for '$FirstName $LastName' after 99 attempts."
}

function Get-TcRandomPassword {
    <#
    .SYNOPSIS
        Returns a random one-time password as a SecureString.
    .DESCRIPTION
        Uses the cryptographic random number generator, guarantees one
        character from each class (upper, lower, digit, symbol) and avoids
        look-alike characters (0/O, 1/l/I) so it can be read out on day 1.
        The plain text never touches the pipeline, a variable or a log.
    #>
    [CmdletBinding()]
    [OutputType([securestring])]
    param([ValidateRange(14, 128)][int]$Length = 16)

    $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '!#%+-=?@')
    $all = -join $sets
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $pick = {
            param([string]$From)
            $bytes = New-Object byte[] 4
            $rng.GetBytes($bytes)
            $From[[int]([BitConverter]::ToUInt32($bytes, 0) % [uint32]$From.Length)]
        }
        $chars = New-Object System.Collections.Generic.List[char]
        foreach ($s in $sets) { $chars.Add((& $pick $s)) }
        while ($chars.Count -lt $Length) { $chars.Add((& $pick $all)) }
        # Fisher-Yates shuffle so the guaranteed classes are not always first
        for ($i = $chars.Count - 1; $i -gt 0; $i--) {
            $bytes = New-Object byte[] 4
            $rng.GetBytes($bytes)
            $j = [int]([BitConverter]::ToUInt32($bytes, 0) % [uint32]($i + 1))
            $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
        }
        $secure = New-Object System.Security.SecureString
        foreach ($c in $chars) { $secure.AppendChar($c) }
        $chars.Clear()
        $secure.MakeReadOnly()
        return $secure
    }
    finally { $rng.Dispose() }
}

function Get-TcPasswordExpiry {
    <#
    .SYNOPSIS
        Calculates when each account's password expires and whether to notify today.
    .DESCRIPTION
        Input objects need SamAccountName, Enabled, PasswordLastSet and
        PasswordNeverExpires (as returned by Get-ADUser -Properties ...), and
        optionally ExpiresOn (from msDS-UserPasswordExpiryTimeComputed, which
        takes PSO-AdminAccounts into account); without it -MaxPasswordAge is used.
        At TechCorp only privileged accounts expire (PSO-AdminAccounts, 365 days);
        staff passwords never expire (user-accounts.md section 3).
        An account is notified when DaysLeft is exactly one of -NotifyDays
        (default 14, 7, 3, 1) or 0 (expires today) - one e-mail per
        threshold, not one per day - or when it already expired. Disabled accounts, accounts whose
        password never expires and accounts that must change at next logon
        (PasswordLastSet empty) are reported with State and not notified.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Account,
        [timespan]$MaxPasswordAge = (New-TimeSpan -Days 365),
        [int[]]$NotifyDays = @(14, 7, 3, 1),
        [datetime]$Now = (Get-Date)
    )

    foreach ($a in $Account) {
        $state = 'OK'; $expires = $null; $daysLeft = $null
        $enabled = ConvertTo-TcBool $a.Enabled
        $lastSet = ConvertTo-TcDate $a.PasswordLastSet
        if (-not $enabled) { $state = 'Disabled' }
        elseif (ConvertTo-TcBool $a.PasswordNeverExpires) { $state = 'NeverExpires' }
        elseif (-not $lastSet) { $state = 'MustChange' }
        else {
            # AD's own calculation (msDS-UserPasswordExpiryTimeComputed) already
            # honours fine-grained policies - prefer it when the caller supplies it
            $computed = if ($a.PSObject.Properties['ExpiresOn']) { ConvertTo-TcDate $a.ExpiresOn } else { $null }
            $expires = if ($computed) { $computed } else { $lastSet + $MaxPasswordAge }
            $daysLeft = [int][math]::Floor(($expires.Date - $Now.Date).TotalDays)
            if ($daysLeft -lt 0) { $state = 'Expired' }
            elseif ($daysLeft -le ($NotifyDays | Measure-Object -Maximum).Maximum) { $state = 'ExpiringSoon' }
        }
        $notify = ($state -eq 'Expired') -or ($state -eq 'ExpiringSoon' -and ($NotifyDays -contains $daysLeft -or $daysLeft -eq 0))
        [pscustomobject]@{
            SamAccountName = [string]$a.SamAccountName
            DisplayName    = [string]$(if ($a.PSObject.Properties['DisplayName']) { $a.DisplayName } else { '' })
            EmailAddress   = [string]$(if ($a.PSObject.Properties['EmailAddress']) { $a.EmailAddress } else { '' })
            PasswordLastSet = $lastSet
            ExpiresOn      = $expires
            DaysLeft       = $daysLeft
            State          = $state
            Notify         = $notify
        }
    }
}

function Get-TcStaleAccount {
    <#
    .SYNOPSIS
        Classifies user or computer accounts that need attention (stale-account review).
    .DESCRIPTION
        Input objects need SamAccountName (or Name), Enabled, LastLogonDate,
        WhenCreated, and for users PasswordNeverExpires and DistinguishedName.

        Findings (an account can have several):
          Inactive              enabled, last logon older than -InactiveDays
          NeverLoggedOn         enabled, never logged on, created more than -InactiveDays ago
          PasswordNeverExpires  enabled user with the flag set (only allowed for break-glass/service - see -AllowNeverExpires)
          DisabledPastRetention disabled for longer than -DisabledRetentionDays (leaver procedure: delete after 30 days)

        LastLogonDate is lastLogonTimestamp, which replicates only every
        9-14 days - so -InactiveDays below 14 gives false positives.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Account,
        [ValidateRange(14, 3650)][int]$InactiveDays = 45,
        [int]$DisabledRetentionDays = 30,
        [string[]]$AllowNeverExpires = @(),
        [datetime]$Now = (Get-Date)
    )

    foreach ($a in $Account) {
        $name = if ($a.PSObject.Properties['SamAccountName'] -and $a.SamAccountName) { [string]$a.SamAccountName } else { [string]$a.Name }
        $enabled = ConvertTo-TcBool $a.Enabled
        $lastLogon = ConvertTo-TcDate $(if ($a.PSObject.Properties['LastLogonDate']) { $a.LastLogonDate } else { $null })
        $created = ConvertTo-TcDate $(if ($a.PSObject.Properties['WhenCreated']) { $a.WhenCreated } else { $null })
        $changed = ConvertTo-TcDate $(if ($a.PSObject.Properties['WhenChanged']) { $a.WhenChanged } else { $null })
        $neverExpires = $a.PSObject.Properties['PasswordNeverExpires'] -and (ConvertTo-TcBool $a.PasswordNeverExpires)
        $dn = if ($a.PSObject.Properties['DistinguishedName']) { [string]$a.DistinguishedName } else { '' }
        $cutoff = $Now.AddDays(-$InactiveDays)

        $findings = New-Object System.Collections.Generic.List[string]
        if ($enabled) {
            if ($lastLogon -and $lastLogon -lt $cutoff) { $findings.Add('Inactive') }
            if (-not $lastLogon -and $created -and $created -lt $cutoff) { $findings.Add('NeverLoggedOn') }
            if ($neverExpires -and $AllowNeverExpires -notcontains $name) { $findings.Add('PasswordNeverExpires') }
        }
        elseif ($changed -and $changed -lt $Now.AddDays(-$DisabledRetentionDays)) {
            $findings.Add('DisabledPastRetention')
        }
        if ($findings.Count -eq 0) { continue }

        $days = if ($lastLogon) { [int]($Now - $lastLogon).TotalDays } else { $null }
        [pscustomobject]@{
            Name              = $name
            Enabled           = $enabled
            LastLogonDate     = $lastLogon
            DaysSinceLogon    = $days
            WhenCreated       = $created
            Findings          = ($findings -join ', ')
            DistinguishedName = $dn
        }
    }
}

# ------------------------------------------------------------------ assets

function Get-TcWarrantyStatus {
    <#
    .SYNOPSIS
        Warranty end date and status for each asset in hardware-inventory.csv.
    .DESCRIPTION
        The inventory stores WarrantyYears but no purchase date (the office
        is not bought yet), so the in-service date is a parameter - the
        go-live date 2027-02-15 from deployment-plan.md by default - or an
        InServiceDate column if one is added later.
        Status: Expired, ExpiringSoon (within -WarnDays), OK, NoWarranty (empty WarrantyYears).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Asset,
        [datetime]$InServiceDate = '2027-02-15',
        [int]$WarnDays = 90,
        [datetime]$Now = (Get-Date)
    )
    foreach ($a in $Asset) {
        $start = $InServiceDate
        if ($a.PSObject.Properties['InServiceDate'] -and $a.InServiceDate) { $start = [datetime]$a.InServiceDate }
        $years = 0
        $hasWarranty = [int]::TryParse([string]$a.WarrantyYears, [ref]$years) -and $years -gt 0
        $end = $null; $daysLeft = $null; $status = 'NoWarranty'
        if ($hasWarranty) {
            $end = $start.AddYears($years)
            $daysLeft = [int][math]::Floor(($end.Date - $Now.Date).TotalDays)
            $status = if ($daysLeft -lt 0) { 'Expired' } elseif ($daysLeft -le $WarnDays) { 'ExpiringSoon' } else { 'OK' }
        }
        [pscustomobject]@{
            AssetTag    = $a.AssetTag
            Hostname    = $a.Hostname
            Category    = $a.Category
            AssignedTo  = $a.AssignedTo
            WarrantyEnd = $end
            DaysLeft    = $daysLeft
            Warranty    = $status
        }
    }
}

# ------------------------------------------------------------------ servers and files

function Get-TcDiskStatus {
    <#
    .SYNOPSIS
        PASS / WARN / FAIL per volume from free space (Win32_LogicalDisk-like objects).
    .DESCRIPTION
        Needs DeviceID, Size and FreeSpace (bytes). WARN below -WarnPercent
        free, FAIL below -FailPercent free. Volumes with no size (empty card
        readers, unmounted) are skipped.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Disk,
        [string]$ComputerName = $env:COMPUTERNAME,
        [ValidateRange(1, 99)][int]$WarnPercent = 20,
        [ValidateRange(1, 99)][int]$FailPercent = 10
    )
    if ($FailPercent -ge $WarnPercent) { throw '-FailPercent must be lower than -WarnPercent.' }
    foreach ($d in $Disk) {
        $size = [double]$d.Size
        if ($size -le 0) { continue }
        $pct = [math]::Round(100 * [double]$d.FreeSpace / $size, 1)
        $status = if ($pct -lt $FailPercent) { 'FAIL' } elseif ($pct -lt $WarnPercent) { 'WARN' } else { 'PASS' }
        New-TcResult -Check 'Disk free space' -Target "$ComputerName $($d.DeviceID)" -Status $status `
            -Detail ('{0}% free ({1:N1} of {2:N1} GB)' -f $pct, ([double]$d.FreeSpace / 1GB), ($size / 1GB))
    }
}

function Get-TcOldFile {
    <#
    .SYNOPSIS
        Lists files under -Path older than -OlderThanDays (by LastWriteTime) - the
        selection step of Remove-TechCorpOldFile.ps1, kept separate so it can be tested.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateRange(1, 3650)][int]$OlderThanDays,
        [string[]]$Include = @('*'),
        [switch]$Recurse,
        [datetime]$Now = (Get-Date)
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Folder not found: $Path" }
    $cutoff = $Now.AddDays(-$OlderThanDays)
    $params = @{ LiteralPath = $Path; File = $true; Force = $true; ErrorAction = 'SilentlyContinue' }
    if ($Recurse) { $params.Recurse = $true }
    Get-ChildItem @params | Where-Object {
        $file = $_
        $_.LastWriteTime -lt $cutoff -and @($Include | Where-Object { $file.Name -like $_ }).Count -gt 0
    }
}

# ------------------------------------------------------------------ network

function Test-TcTcpPort {
    <#
    .SYNOPSIS
        TCP connect test with a timeout (Test-NetConnection waits ~20 s per closed port
        and does not exist in PowerShell 7 on Linux). Returns $true / $false.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][ValidateRange(1, 65535)][int]$Port,
        [ValidateRange(100, 60000)][int]$TimeoutMs = 1500
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync($ComputerName, $Port)
        if (-not $task.Wait($TimeoutMs)) { return $false }
        return $client.Connected
    }
    catch { return $false }
    finally { $client.Dispose() }
}

function ConvertFrom-TcStripchart {
    <#
    .SYNOPSIS
        Parses `w32tm /stripchart /dataonly` output and returns the clock offset in seconds.
    .DESCRIPTION
        Data lines look like "09:15:02, +00.0123456s" (or "-01.5000000s").
        Returns the median of the samples ($null if none parsed, e.g.
        "error: 0x800705B4" when the source is unreachable). Kerberos fails
        above 300 s (SC-INF-001); the health check warns far earlier.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Line)

    $values = @(foreach ($l in $Line) {
        if ($l -match ',\s*([+-]\d+(?:[.,]\d+)?)s\s*$') {
            [double]::Parse(($Matches[1] -replace ',', '.'), [Globalization.CultureInfo]::InvariantCulture)
        }
    })
    if ($values.Count -eq 0) { return $null }
    $sorted = @($values | Sort-Object)
    $mid = [int][math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) { return $sorted[$mid] }
    return ($sorted[$mid - 1] + $sorted[$mid]) / 2
}

function Get-TcPasswordExpiryMessage {
    <#
    .SYNOPSIS
        Subject and body of the password-expiry reminder for one account
        (output of Get-TcPasswordExpiry). Plain text, no links - users are
        taught never to click a "change your password" link (phishing).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Expiry,
        [string]$Helpdesk = 'helpdesk@techcorp.example'
    )
    $when = if ($Expiry.ExpiresOn) { ([datetime]$Expiry.ExpiresOn).ToString('dddd d MMMM yyyy', [Globalization.CultureInfo]::InvariantCulture) } else { 'soon' }
    if ($Expiry.State -eq 'Expired') {
        $subject = "Password for $($Expiry.SamAccountName) has expired"
        $first = "The password of the account $($Expiry.SamAccountName) expired on $when. You cannot sign in with it until it is changed."
    }
    else {
        $days = switch ($Expiry.DaysLeft) { 0 { 'today' } 1 { 'in 1 day' } default { "in $_ days" } }
        $subject = "Password for $($Expiry.SamAccountName) expires $days"
        $first = "The password of the account $($Expiry.SamAccountName) expires $days, on $when."
    }
    $body = @(
        $first
        ''
        'Change it before then: sign in with that account and press Ctrl+Alt+Del > Change a password,'
        'or use your password manager to generate a new one (20 characters for admin accounts).'
        ''
        'IT will never send you a link to change your password. If an e-mail like that arrives, report it as phishing.'
        "Questions: $Helpdesk"
        ''
        '-- TechCorp IT (automatic message)'
    ) -join [Environment]::NewLine
    [pscustomobject]@{ Subject = $subject; Body = $body }
}

# ------------------------------------------------------------------ reports

function ConvertTo-TcHtmlReport {
    <#
    .SYNOPSIS
        Builds a self-contained HTML report (no external CSS/JS) from titled tables.
    .DESCRIPTION
        -Section is an ordered hashtable: heading => objects. Every value is
        HTML-encoded. Cells whose text is PASS/WARN/FAIL/SKIP (or a status
        word such as Expired) are colour-coded.
    .EXAMPLE
        ConvertTo-TcHtmlReport -Title 'Daily check' -Section ([ordered]@{ 'Disks' = $results }) | Set-Content report.html
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Section,
        [datetime]$Now = (Get-Date)
    )
    $enc = { param($v) [System.Net.WebUtility]::HtmlEncode([string]$v) }
    $classes = @{ PASS = 'ok'; OK = 'ok'; WARN = 'warn'; ExpiringSoon = 'warn'; FAIL = 'fail'; Expired = 'fail'; SKIP = 'skip' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en"><head><meta charset="utf-8"><title>' + (& $enc $Title) + '</title>')
    [void]$sb.AppendLine('<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#1f2328}table{border-collapse:collapse;margin-bottom:24px;font-size:13px}th,td{border:1px solid #d0d7de;padding:4px 8px;text-align:left}th{background:#f6f8fa}.ok{background:#dafbe1}.warn{background:#fff8c5}.fail{background:#ffebe9}.skip{color:#656d76}</style>')
    [void]$sb.AppendLine('</head><body>')
    [void]$sb.AppendLine('<h1>' + (& $enc $Title) + '</h1>')
    [void]$sb.AppendLine('<p>Generated ' + (& $enc $Now.ToString('yyyy-MM-dd HH:mm')) + ' by ' + (& $enc $env:USERNAME) + '</p>')
    foreach ($heading in $Section.Keys) {
        $rows = @($Section[$heading])
        [void]$sb.AppendLine('<h2>' + (& $enc $heading) + ' (' + $rows.Count + ')</h2>')
        if ($rows.Count -eq 0) { [void]$sb.AppendLine('<p>Nothing to report.</p>'); continue }
        $columns = @($rows[0].PSObject.Properties | ForEach-Object { $_.Name })
        [void]$sb.Append('<table><tr>')
        foreach ($c in $columns) { [void]$sb.Append('<th>' + (& $enc $c) + '</th>') }
        [void]$sb.AppendLine('</tr>')
        foreach ($r in $rows) {
            [void]$sb.Append('<tr>')
            foreach ($c in $columns) {
                $value = $r.$c
                if ($value -is [datetime]) { $value = $value.ToString('yyyy-MM-dd') }
                $text = [string]$value
                $class = if ($classes.ContainsKey($text)) { ' class="' + $classes[$text] + '"' } else { '' }
                [void]$sb.Append("<td$class>" + (& $enc $text) + '</td>')
            }
            [void]$sb.AppendLine('</tr>')
        }
        [void]$sb.AppendLine('</table>')
    }
    [void]$sb.AppendLine('</body></html>')
    return $sb.ToString()
}

# ------------------------------------------------------------------ small converters

function ConvertTo-TcBool {
    <#
    .SYNOPSIS
        Accepts $true/$false and the strings True/False/Yes/No/1/0 (CSV exports).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return $Value }
    return ([string]$Value).Trim() -in 'True', 'Yes', '1', 'Y'
}

function ConvertTo-TcDate {
    <#
    .SYNOPSIS
        Accepts [datetime], ISO strings and empty values (returns $null).
    #>
    [CmdletBinding()]
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value }
    $text = ([string]$Value).Trim()
    if (-not $text) { return $null }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) { return $parsed }
    throw "Not a date: '$text'"
}

Export-ModuleMember -Function @(
    'Get-TcRepoRoot', 'Import-TcData', 'ConvertTo-TcOuDn',
    'Write-TcLog', 'New-TcResult', 'Get-TcOverallStatus', 'Get-TcExitCode',
    'ConvertTo-TcAsciiName', 'Get-TcUsername', 'Get-TcRandomPassword',
    'Get-TcPasswordExpiry', 'Get-TcStaleAccount', 'Get-TcWarrantyStatus',
    'Get-TcDiskStatus', 'Get-TcOldFile', 'Test-TcTcpPort', 'ConvertFrom-TcStripchart', 'Get-TcPasswordExpiryMessage',
    'ConvertTo-TcHtmlReport', 'ConvertTo-TcBool', 'ConvertTo-TcDate'
)
