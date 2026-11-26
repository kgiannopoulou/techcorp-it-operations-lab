# 03 – Windows Server

**Status:** ⏳ Planned – Phases 2–3 (M5–M6)

Installing and operating Windows Server 2025 on TC-HV01: Active Directory, DNS, DHCP, Group Policy, file services and permissions.

## Planned contents

| Folder | Contents |
|---|---|
| `installation/` | Hyper-V host and VM builds (TC-DC01, TC-DC02, TC-FS01) |
| `active-directory/` | Domain `corp.techcorp.example`, second DC, FSMO roles, replication |
| `users-and-groups/` | OU design, AGDLP groups, bulk creation from `employees.csv` |
| `group-policy/` | Baseline GPOs, BitLocker, LAPS, drive and printer mappings |
| `dns/` | AD-integrated zones, forwarders, scavenging |
| `dhcp/` | DHCP Server role as an exercise (production DHCP runs on the firewall – see NET-CHG-001) |
| `file-services/` | Shares, DFS namespace, quotas, shadow copies |
| `permissions/` | NTFS vs share permissions, effective access |
