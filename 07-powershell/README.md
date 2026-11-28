# 07 – PowerShell

**Status:** 🟡 Milestone 8 done (administrative scripts + Pester tests, CI green) – network diagnostics (M4) · Active Directory (M5) · endpoints and Microsoft 365 (M6) · lab runs against a live domain pending

Automation scripts that replace repetitive manual work. Every script has
comment-based help (`Get-Help <script> -Full`), runs on Windows PowerShell 5.1
and PowerShell 7, has no hard-coded credentials, and is checked by
PSScriptAnalyzer **and Pester tests** in CI.

## Milestone 8 – administrative scripts

Day-to-day administration for one IT person (BR-32): joiners and leavers,
reviews nobody remembers to do, and a morning check that says in one page
whether anything is wrong. The logic lives in one shared module so it can be
unit tested; the scripts do the I/O.

| Script | Job | Runs on | Changes anything? |
|---|---|---|---|
| [user-management/New-TechCorpUser.ps1](user-management/New-TechCorpUser.ps1) | **Joiner** (BR-10): validates the HR request, unique logon name, next employee ID, spare laptop, OU + groups from the CSVs, creates the AD account (disabled until the start date), one-time password shown once; prints the `employees.csv` row to commit. `-PlanOnly` offline | DC / admin PC (RSAT) | Yes – `-WhatIf` |
| [user-management/Disable-TechCorpUser.ps1](user-management/Disable-TechCorpUser.ps1) | **Leaver** (BR-10): safety checks, group record (= rollback), revoke sessions, mailbox → shared + manager access + out-of-office, disable, reset, remove groups, move to `Disabled` – in the order that keeps the mailbox | DC / admin PC (+ Graph, EXO) | Yes – `-WhatIf`, ConfirmImpact High |
| [reporting/Get-TechCorpStaleAccountReport.ps1](reporting/Get-TechCorpStaleAccountReport.ps1) | Monthly review (BR-26): inactive, never-used, password-never-expires and past-retention users and computers → CSV + HTML | DC / admin PC | No |
| [reporting/Send-TechCorpPasswordExpiryNotice.ps1](reporting/Send-TechCorpPasswordExpiryNotice.ps1) | Reminds owners of `adm-`/`wadm-` accounts (PSO 365 days) at 14/7/3/1/0 days, from AD's own computed expiry | DC / admin PC | Sends mail only with `-SmtpServer` – `-WhatIf` |
| [reporting/Get-TechCorpInventoryReport.ps1](reporting/Get-TechCorpInventoryReport.ps1) | Asset report (BR-28): counts, warranty end, spare stock, laptops held by leavers; `-Live` collects model/serial/OS/RAM/disk over CIM | Anywhere | No |
| [maintenance/Get-TechCorpServerHealth.ps1](maintenance/Get-TechCorpServerHealth.ps1) | Uptime, disks, pending reboot, role services from `data/server-roles.csv`, stopped automatic services, System-log errors, clock offset | Admin PC → servers (WinRM) | No |
| [maintenance/Remove-TechCorpOldFile.ps1](maintenance/Remove-TechCorpOldFile.ps1) | Retention clean-up of reports/logs with safety rails (no drive roots, system or profile folders) | Servers | Yes – `-WhatIf` |
| [maintenance/Invoke-TechCorpDailyCheck.ps1](maintenance/Invoke-TechCorpDailyCheck.ps1) | The 08:30 check: health + service ports + stale accounts + password expiry → one HTML page, exit code for a scheduled task | TC-FS01 (scheduled, gMSA) | Only the e-mail with `-MailTo` |
| [network-diagnostics/Test-TechCorpServicePort.ps1](network-diagnostics/Test-TechCorpServicePort.ps1) | Every server/device answers on the TCP ports its role needs (DNS, Kerberos, LDAP, SMB, ADWS, WinRM, printer ports) | MGMT VLAN | No |
| [modules/TechCorp.Admin](modules/TechCorp.Admin/TechCorp.Admin.psm1) | 21 shared functions: logon names, random passwords, expiry/stale/warranty/disk rules, TCP test, HTML report, logging, PASS/WARN/FAIL results | – | No |

```powershell
# offline - any PC
./07-powershell/user-management/New-TechCorpUser.ps1 -Path ./07-powershell/user-management/new-starters.example.csv -PlanOnly
./07-powershell/reporting/Get-TechCorpInventoryReport.ps1 -Now 2029-12-01
./07-powershell/maintenance/Get-TechCorpServerHealth.ps1          # this computer
# lab domain (MGMT VLAN, adm- account)
.\Disable-TechCorpUser.ps1 -Identity connie.springer -Ticket HD-2027-0042 -WhatIf
.\Invoke-TechCorpDailyCheck.ps1 -TimeSource TC-DC01
```

### Script standards

| Rule | How it is enforced |
|---|---|
| Comment-based help with synopsis, description and at least one example | `tests/ScriptStandards.Tests.ps1` |
| `[CmdletBinding()]`; anything that changes state supports `-WhatIf` / `-Confirm` | Pester (verbs Deploy/Disable/Install/New/Remove/Send/Set) |
| No credentials in code; passwords only as `SecureString`, generated, shown once, never logged | Pester (pattern scan) + onboarding test that the password is not in the record or log |
| Plain ASCII files – Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI | Pester |
| Data from the repository CSVs, never hard-coded in a script | Review; `Import-TcData` is the only reader |
| Results as `Check / Target / Status / Detail` rows; exit code 0 PASS, 1 WARN, 2 FAIL | `Get-TcExitCode`, unit tested |
| Evidence: CSV/HTML to `output/` (git-ignored), log lines `timestamp [LEVEL] message` | `Write-TcLog`, unit tested |
| Errors, warnings: PSScriptAnalyzer clean | CI |

### Tests

[tests/](tests/) holds **248 Pester tests** (Pester 5 and 6), run in CI on Linux (PowerShell 7)
and Windows (Windows PowerShell 5.1 and PowerShell 7):

| Suite | What it proves |
|---|---|
| `TechCorp.Admin.Tests.ps1` | Every module function: name folding (`Zoë` → `zoe`), 20-character limit and collisions, password classes and uniqueness, expiry thresholds incl. PSO, stale-account rules, warranty, disks, exit codes, log format, file age selection, TCP against a real listener, `w32tm` parsing, HTML encoding |
| `UserManagement.Tests.ps1` | Joiner plan from the example CSV; collisions with `employees.csv` **and** AD; invalid rows rejected; account created disabled for a future start; password never in record/log. Leaver: exact order of the 10 changes, record before removal, `Domain Users` kept, stop when the mailbox conversion fails, refusals (admin, Domain Admins, built-in), `-WhatIf` changes nothing |
| `Reporting.Tests.ps1` | Stale and expiry reports on fixture exports; owner mapping for `adm-` accounts; inventory report on the repository data and on a fixture with a leaver's laptop |
| `Maintenance.Tests.ps1` | Clean-up on real files (age, pattern, recursion, `-WhatIf`, refusal of drive root and repository); port test against a real listener; health check and daily check on the Windows runner |
| `ScriptStandards.Tests.ps1` | The standards table above, for every script in this folder |

AD, Graph and Exchange Online do not exist on a CI runner: the tests replace
them with stub functions and Pester mocks. That proves **what** a script would
change and in **which order** – not that a real domain accepts it; that is the
lab run (M5 lab), still pending.

```powershell
Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -SkipPublisherCheck   # once; Windows ships Pester 3.4
./07-powershell/tests/Invoke-TechCorpTests.ps1 -Output Detailed
```

### Scheduling

| Task | When | Command |
|---|---|---|
| Daily check | Mon–Fri 08:00 | `Invoke-TechCorpDailyCheck.ps1 -TimeSource TC-DC01 -MailTo it@techcorp.example -SmtpServer <relay>` |
| Password reminders | Daily 07:30 | `Send-TechCorpPasswordExpiryNotice.ps1 -SmtpServer <relay>` |
| Stale-account review | 1st working day of the month | `Get-TechCorpStaleAccountReport.ps1` → reviewed and signed off by the Operations Manager |
| Inventory report | Monthly + before budget planning | `Get-TechCorpInventoryReport.ps1 -Live -ComputerName (laptops)` |
| Report clean-up | Sunday 03:00 | `Remove-TechCorpOldFile.ps1 -Path D:\Shares\IT\Reports -OlderThanDays 90 -Recurse -Force -Confirm:$false` |

Tasks run on TC-FS01 as a gMSA (no stored password – Phase 10), from a
`git clone` of this repository, so the scripts are never marked as downloaded
(SC-PS-001). The registration command is in the help of
`Invoke-TechCorpDailyCheck.ps1`.

### Design changes in Milestone 8

| ID | Change | Why |
|---|---|---|
| PS-CHG-001 | Joiner accounts are created by `New-TechCorpUser.ps1`, **disabled until the start date**; `employees.csv` gets the row afterwards (printed by the script). `Deploy-TechCorpAd.ps1` stays for the initial bulk build and for keeping attributes in line | An enabled account with a known one-time password, sitting unused for weeks before day 1, is an easy target; one person creating one account should not need a full domain deploy |
| PS-CHG-002 | Password-expiry reminders only matter for `adm-`/`wadm-` accounts and are sent to the **owner's** mailbox, using AD's computed expiry (`msDS-UserPasswordExpiryTimeComputed`) | Staff passwords never expire (user-accounts.md §3); admin accounts have no mailbox; computing from the domain policy would ignore `PSO-AdminAccounts` |

Data the scripts need and no earlier CSV had – which services and ports each
server role must offer – is in [data/server-roles.csv](data/server-roles.csv)
(Pester checks every host exists in the hardware inventory).

Scenarios: [14-scenarios/automation](../14-scenarios/automation/) (SC-PS-001 … 005) · Lessons: [m8-powershell-administration.md](../15-documentation/lessons-learned/m8-powershell-administration.md).

## Earlier milestones' scripts

| Script | Purpose | Changes anything? |
|---|---|---|
| [network-diagnostics/Get-SubnetInfo.ps1](network-diagnostics/Get-SubnetInfo.ps1) | IPv4 subnet calculator (network, mask, wildcard, hosts). `-SelfTest` runs 12 test cases in CI | No |
| [network-diagnostics/Test-TechCorpNetwork.ps1](network-diagnostics/Test-TechCorpNetwork.ps1) | Client-side check of IP config, gateway, DNS and the inter-VLAN firewall policy; PASS/FAIL/SKIP table + CSV evidence | No (read-only probes) |

```powershell
./07-powershell/network-diagnostics/Get-SubnetInfo.ps1 10.10.50.200/26
./07-powershell/network-diagnostics/Test-TechCorpNetwork.ps1 -OutputPath .\output\staff.csv
```

### Active Directory (Milestone 5)

All five scripts read the same plan, built from the CSVs in
[03-windows-server](../03-windows-server/) – change the CSV, not the script.

| Script | Purpose | Runs on | Changes anything? |
|---|---|---|---|
| [active-directory/Get-TechCorpAdPlan.ps1](active-directory/Get-TechCorpAdPlan.ps1) | Builds the plan offline; `-SelfTest` validates naming, AGDLP, GPO targets and 65 effective-access tests (CI); `-Summary` prints the access matrix | Anywhere | No |
| [active-directory/Deploy-TechCorpAd.ps1](active-directory/Deploy-TechCorpAd.ps1) | OUs, groups, users, `adm-`/`wadm-` accounts, memberships, delegation, PSO, machine quota | TC-DC01 | Yes – idempotent, `-WhatIf` |
| [active-directory/Deploy-TechCorpGpo.ps1](active-directory/Deploy-TechCorpGpo.ps1) | GPOs, links, security filtering, registry settings, LAPS preparation | TC-DC01 | Yes – idempotent, `-WhatIf` |
| [active-directory/Deploy-TechCorpFileShare.ps1](active-directory/Deploy-TechCorpFileShare.ps1) | Folders, NTFS ACLs, SMB shares with ABE, DFS namespace | TC-FS01 | Yes – idempotent, `-WhatIf` |
| [active-directory/Test-TechCorpAd.ps1](active-directory/Test-TechCorpAd.ps1) | Compares the live domain and file server with the plan; PASS/FAIL/SKIP + CSV evidence | TC-DC01 | No |

```powershell
./07-powershell/active-directory/Get-TechCorpAdPlan.ps1 -SelfTest
./07-powershell/active-directory/Get-TechCorpAdPlan.ps1 -Summary
.\Deploy-TechCorpAd.ps1 -WhatIf
.\Test-TechCorpAd.ps1 -FileServer TC-FS01 -OutputPath .\output\ad.csv
```

Not yet run against a live domain: the deploy and test scripts are checked by
PSScriptAnalyzer in CI; their first real run is part of the M5 lab.

### Endpoints and Microsoft 365 (Milestone 6)

| Script | Purpose | Runs on | Changes anything? |
|---|---|---|---|
| [endpoint/Install-TechCorpBaseline.ps1](endpoint/Install-TechCorpBaseline.ps1) | Installs the apps for the laptop's owner from `app-catalogue.csv` (winget, ODT, RSAT, WSL); `-ListOnly`; `-SelfTest` validates the catalogue (CI) | Laptop | Yes – idempotent, `-WhatIf` |
| [endpoint/Test-TechCorpEndpoint.ps1](endpoint/Test-TechCorpEndpoint.ps1) | Build check: asset/hostname, edition, domain + hybrid join, PRT, TPM, Secure Boot, BitLocker, Defender, firewall, local admins, LAPS, GPOs, clock, apps | Laptop | No |
| [microsoft-365/Get-TechCorpM365Plan.ps1](microsoft-365/Get-TechCorpM365Plan.ps1) | M365 plan offline; `-SelfTest` validates admins, mailboxes, teams, sharing (CI); `-Summary` shows team membership | Anywhere | No |
| [microsoft-365/Deploy-TechCorpM365.ps1](microsoft-365/Deploy-TechCorpM365.ps1) | Usage location, group licensing, shared/room mailboxes, dynamic groups → Teams + channels, SharePoint sharing | Admin PC (Graph, EXO, Teams, SPO modules) | Yes – idempotent, `-WhatIf` |
| [microsoft-365/Test-TechCorpM365.ps1](microsoft-365/Test-TechCorpM365.ps1) | Compares the tenant with the plan; PASS/FAIL/SKIP + CSV | Admin PC | No |

Every M365 script takes `-LabTenant -TenantDomain <tenant>.onmicrosoft.com`
for the lab (the fictional domain cannot be verified).

## Still to come

| Script | Milestone |
|---|---|
| Licence report (assigned vs `employees.csv`, unused licences) – needs the lab tenant | M7 / M12 |
| BitLocker / Defender / patch-level status report from Intune | M7, M10 |
| Backup job and restore-test report | M11 |
| First run of every M8 script against the lab domain, with the CSV/HTML evidence in `16-reports/` | M5 lab |
