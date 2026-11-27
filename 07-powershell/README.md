# 07 – PowerShell

**Status:** 🟡 Started – network diagnostics (M4) · Active Directory (M5) · endpoints and Microsoft 365 (M6) · full automation in Phase 8 (M9)

Automation scripts that replace repetitive manual work. Every script has
comment-based help (`Get-Help <script> -Full`), runs on Windows PowerShell 5.1
and PowerShell 7, has no hard-coded credentials, and is checked by
PSScriptAnalyzer in CI.

## Available scripts

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

## Planned contents

| Folder | Contents |
|---|---|
| `scripts/` | General utilities |
| `user-management/` | Onboarding / offboarding automation (bulk creation already in `active-directory/`) |
| `network-diagnostics/` | More connectivity, DNS and port tests |
| `reporting/` | Inventory, licence, stale-account and BitLocker status reports |
