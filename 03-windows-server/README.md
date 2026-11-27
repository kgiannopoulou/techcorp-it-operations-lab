# 03 – Windows Server and Active Directory

**Status:** ✅ Milestone 5 – designed, scripted and documented · 🧪 lab execution and evidence pending

Windows Server 2025 on TC-HV01 (lab: VirtualBox): the `corp.techcorp.example`
domain, users, groups, OUs, Group Policy, the file server and its permissions.

Everything identity-related is **data first**: the CSV files below are the
single source of truth, `Get-TechCorpAdPlan.ps1 -SelfTest` validates them in
CI (naming, AGDLP, GPO link targets, 65 effective-access tests), and the
deploy scripts in [07-powershell/active-directory](../07-powershell/active-directory/)
build the domain from them.

## Build order

| # | Document | ID | What you end up with |
|---|---|---|---|
| 1 | [installation/server-build.md](installation/server-build.md) | WIN-PRC-001 | TC-DC01, TC-DC02, TC-FS01 VMs, static IPs, patched |
| 2 | [active-directory/ad-ds-deployment.md](active-directory/ad-ds-deployment.md) | WIN-PRC-002 | Forest, second DC, site/subnets, PDC time, Recycle Bin, FSMO |
| 3 | [dns/ad-integrated-dns.md](dns/ad-integrated-dns.md) | WIN-PRC-003 | AD DNS zones, forwarder, scavenging, clients switched to the DCs |
| 4 | [users-and-groups/user-accounts.md](users-and-groups/user-accounts.md) | WIN-PRC-004 | 20 staff accounts, `adm-`/`wadm-` accounts, password policy + PSO, lifecycle |
| 5 | [group-policy/gpo-procedures.md](group-policy/gpo-procedures.md) | WIN-PRC-005 | 13 GPOs built and verified with `gpresult` |
| 6 | [file-services/file-server.md](file-services/file-server.md) | WIN-PRC-006 | Shares, DFS namespace, quotas, file screen, shadow copies |

## Design references

| Document | ID | Contents |
|---|---|---|
| [users-and-groups/ou-design.md](users-and-groups/ou-design.md) | WIN-REF-001 | OU tree, design rules, delegation |
| [users-and-groups/groups-agdlp.md](users-and-groups/groups-agdlp.md) | WIN-REF-002 | AGDLP, every group, CI-enforced rules |
| [group-policy/gpo-design.md](group-policy/gpo-design.md) | WIN-REF-003 | Principles, processing order, GPO catalogue, drive maps |
| [permissions/ntfs-and-share-permissions.md](permissions/ntfs-and-share-permissions.md) | WIN-REF-004 | Share vs NTFS, access levels, effective-access matrix |
| [active-directory/ad-troubleshooting.md](active-directory/ad-troubleshooting.md) | WIN-REF-005 | Method, commands, event IDs, symptom table |

## Source data (CI-validated)

| File | Contents |
|---|---|
| [users-and-groups/ou-structure.csv](users-and-groups/ou-structure.csv) | 23 OUs |
| [users-and-groups/department-map.csv](users-and-groups/department-map.csv) | Department → code, OU, role group, folder |
| [users-and-groups/ad-groups.csv](users-and-groups/ad-groups.csv) | 28 groups and their members |
| [users-and-groups/admin-accounts.csv](users-and-groups/admin-accounts.csv) | Privileged accounts |
| [group-policy/gpo-plan.csv](group-policy/gpo-plan.csv) | 13 GPOs: link, filtering, method |
| [group-policy/gpo-registry-settings.csv](group-policy/gpo-registry-settings.csv) | 35 registry-based settings |
| [file-services/folders.csv](file-services/folders.csv) | 12 folders, shares, inheritance |
| [permissions/file-permissions.csv](permissions/file-permissions.csv) | 14 folder grants (DL groups only) |
| [permissions/access-tests.csv](permissions/access-tests.csv) | 25 expected-access assertions |

Users come from [employees.csv](../00-company-overview/data/employees.csv)
and computers from [hardware-inventory.csv](../01-office-deployment/equipment-inventory/hardware-inventory.csv).

## Design changes in Milestone 5

| ID | Change | Why |
|---|---|---|
| [WIN-CHG-001](users-and-groups/user-accounts.md#2-privileged-accounts--design-change-win-chg-001) | Separate `wadm-` workstation admin account; Domain Admins denied logon on laptops | One admin account would have exposed Domain Admin credentials on the most exposed machines |
| [WIN-CHG-002](file-services/file-server.md#design-change-win-chg-002--dfsit-becomes-dfsit) | DFS folder `dfs\IT$` → `dfs\IT` (share stays `IT$`) | `$` hides SMB shares, not namespace folders |
| WIN-CHG-003 | Short department codes (`Sales`, `Development`, …) in OU and group names | `Sales & Marketing` contains `&` and spaces – awkward in DNs, filters and scripts ([naming-conventions.md](../15-documentation/standards/naming-conventions.md#4-groups)) |

## Not in this milestone

- Windows DHCP Server role exercise – production DHCP stays on the firewall (NET-CHG-001); optional lab exercise later.
- Printer deployment GPO (Phase 4), Entra Connect (Phase 5), backups of AD and file data (Phase 10).

Scenarios: [14-scenarios/windows](../14-scenarios/windows/),
[accounts](../14-scenarios/accounts/), [infrastructure](../14-scenarios/infrastructure/).
Lessons: [m5-windows-server-ad.md](../15-documentation/lessons-learned/m5-windows-server-ad.md).
