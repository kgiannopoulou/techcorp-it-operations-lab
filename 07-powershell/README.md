# 07 – PowerShell

**Status:** 🟡 Started – network diagnostics (Milestone 4) · full automation in Phase 8 (M11)

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

## Planned contents

| Folder | Contents |
|---|---|
| `scripts/` | General utilities |
| `user-management/` | Onboarding / offboarding, bulk users from `employees.csv` |
| `network-diagnostics/` | More connectivity, DNS and port tests |
| `reporting/` | Inventory, licence, stale-account and BitLocker status reports |
