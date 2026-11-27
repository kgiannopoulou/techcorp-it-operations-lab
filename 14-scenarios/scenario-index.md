# Scenario Index

| Field | Value |
|---|---|
| Document ID | SC-REF-001 |
| Owner | IT Specialist |
| Status | Living document |
| Last reviewed | 2026-11-27 |

Every practical problem in the lab, by area. **Status** is honest: *Designed*
means the scenario and its expected investigation are written; *Solved* means
I actually performed it in the lab and attached evidence.

| ID | Title | Difficulty | Phase | Status |
|---|---|---|---|---|
| [SC-NET-001](networking/sc-net-001-staff-pc-no-ip.md) | Nobody in the open plan can get on the network after a switch change | ⭐⭐ | 1 – Network | Designed |
| [SC-NET-002](networking/sc-net-002-native-vlan-mismatch.md) | Switch log full of native VLAN mismatch messages | ⭐⭐ | 1 – Network | Designed |
| [SC-NET-003](networking/sc-net-003-guest-reaches-internal.md) | A visitor's laptop can open the internal file server | ⭐⭐⭐ | 1 – Network | Designed |
| [SC-NET-004](networking/sc-net-004-internet-by-ip-not-by-name.md) | Teams call keeps working but no website opens | ⭐ | 1 – Network | Designed |
| [SC-NET-005](networking/sc-net-005-desk-port-err-disabled.md) | Desk port dead after a user brought in a mini switch | ⭐ | 1 – Network | Designed |
| [SC-WIN-001](windows/sc-win-001-domain-join-fails-dns.md) | New laptop cannot join the domain | ⭐ | 2 – Windows Server | Designed |
| [SC-WIN-002](windows/sc-win-002-gpo-security-filtering.md) | Finance can write to USB sticks again | ⭐⭐⭐ | 3 – Group Policy | Designed |
| [SC-WIN-003](windows/sc-win-003-user-gpo-linked-to-computers.md) | Nobody gets the new Managers drive | ⭐⭐ | 3 – Group Policy | Designed |
| [SC-ACC-001](accounts/sc-acc-001-repeated-lockout.md) | Account locked out every morning | ⭐⭐ | 3 – Accounts | Designed |
| [SC-ACC-002](accounts/sc-acc-002-new-group-member-access-denied.md) | Added to Finance – still "Access denied" | ⭐ | 3 – Accounts | Designed |
| [SC-ACC-003](accounts/sc-acc-003-payroll-inputs-traverse.md) | Payroll officer cannot "find" the payroll inputs | ⭐⭐ | 3 – Permissions | Designed |
| [SC-ACC-004](accounts/sc-acc-004-deleted-user-recycle-bin.md) | The wrong Ackerman was deleted | ⭐⭐ | 3 – Accounts | Designed |
| [SC-INF-001](infrastructure/sc-inf-001-kerberos-clock-skew.md) | "The time difference between the client and server is too large" | ⭐⭐ | 2 – Windows Server | Designed |

## Counts

| Area | Designed | Solved |
|---|---:|---:|
| Networking | 5 | 0 |
| Hardware | 0 | 0 |
| Windows | 3 | 0 |
| Accounts | 4 | 0 |
| Microsoft 365 | 0 | 0 |
| Security | 0 | 0 |
| Infrastructure | 1 | 0 |
