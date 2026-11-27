# Hybrid Identity with Microsoft Entra Connect Sync

| Field | Value |
|---|---|
| Document ID | M365-PRC-002 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved after the lab sync runs |
| Last reviewed | 2026-11-27 |
| Related requirements | BR-01, BR-10, BR-11 |
| Source data | [ou-structure.csv](../../03-windows-server/users-and-groups/ou-structure.csv) (`EntraSync` column) |

## Purpose

One identity per person (BR-01): the AD account created from
`employees.csv` becomes the Microsoft 365 account, with the same UPN
(`firstname.lastname@techcorp.example`) and password, and laptops become
*hybrid Entra joined* so users get single sign-on to Microsoft 365.

## Design

| Decision | Choice | Why |
|---|---|---|
| Sync engine | **Entra Connect Sync** (not Cloud Sync) | Hybrid join needs computer objects synced – Cloud Sync does not sync devices |
| Server | **TC-SYNC01** (new VM, 10.10.30.13, Desktop Experience) – *lab: on TC-DC01* | The sync server holds credentials that can change AD and the tenant → it is a **Tier 0** asset, kept off the file server. TC-HV01's two Server Standard licences cover four VMs, so it costs nothing extra |
| Sign-in method | **Password hash synchronisation (PHS)** | Users can still sign in to M365 if the office/DCs are down (BR-19); enables leaked-credential detection; no on-prem agents |
| Seamless SSO | Off | Hybrid-joined Windows 11 already gets SSO from the Primary Refresh Token |
| Source anchor | `ms-DS-ConsistencyGuid` (default) | Survives a forest rebuild |
| Device options | **Configure hybrid Microsoft Entra join** (creates the SCP for Windows 10+ devices) | Laptops register automatically |
| Password writeback | Off now, on in M7 with SSPR | SSPR is designed with MFA/Conditional Access |
| Group writeback | Off | All cloud groups are cloud-managed (dynamic) |

### Sync scope (OU filtering)

From the `EntraSync` column of `ou-structure.csv` – CI fails if it is changed in
a way that breaks these rules:

| Synced | Not synced |
|---|---|
| `TechCorp/Users/*` – 20 staff | `TechCorp/Admin/*` – privileged accounts never leave AD |
| `TechCorp/Computers/Workstations/*` – hybrid join | `TechCorp/Computers/Servers` – servers are not joined to Entra |
| `TechCorp/Groups/Licensing` – `LIC_M365_BusinessPremium` | `TechCorp/Groups/Role`, `Resource` – on-prem file access only |
| `TechCorp/Disabled` – **M365-CHG-002** | built-in containers (`CN=Users`, `CN=Computers`) |

### Design change M365-CHG-002 – the Disabled OU is synced

M5 left the leavers' OU out of everything. If it is out of the sync scope, a
leaver moved there is **deleted** from Entra ID by the next sync: the mailbox
becomes inaccessible, and OneDrive starts its deletion countdown – exactly
what HR needs to keep for handover (SC-M365-003). Syncing `Disabled` means a
leaver's cloud account is *blocked* (AD `Enabled = False` syncs as
`accountEnabled = false`) and the mailbox/OneDrive are handled deliberately
in the leaver procedure ([licensing-and-lifecycle.md](../user-management/licensing-and-lifecycle.md)).

## Prerequisites

- [ ] UPN suffix `techcorp.example` registered in the forest (`Deploy-TechCorpAd.ps1` step 0) and the domain verified in the tenant (production)
- [ ] Run **IdFix** against `TechCorp/Users` – no duplicate proxy addresses, no invalid characters
- [ ] TC-SYNC01 built per [server-build.md](../../03-windows-server/installation/server-build.md) (Desktop Experience), joined to `TechCorp/Computers/Servers`, TLS 1.2 enabled (default on 2025)
- [ ] An **Enterprise Admin** for the install (temporarily add `adm-eren.yeager`, remove afterwards) and the cloud `adm-eren.yeager` (Hybrid Identity Administrator)
- [ ] Firewall: SERVERS → internet already allowed (rule 4)

## Procedure

1. Download *Microsoft Entra Connect Sync* from the Entra admin center (*Entra Connect → Get started*) on TC-SYNC01.
2. **Customize** (not Express): *Use an existing SQL* – No (SQL Express LocalDB); sign-in **Password Hash Synchronization**.
3. Connect to Entra ID with `adm-eren.yeager@<tenant>`; connect the directory `corp.techcorp.example` with *Create new AD account* (the wizard creates `MSOL_…` with the minimum rights) using the Enterprise Admin.
4. *Microsoft Entra sign-in configuration*: UPN suffix `techcorp.example` shows **Verified** (lab: *Not added* → users get `@<tenant>.onmicrosoft.com` – expected, continue with *without matching all UPN suffixes*).
5. **Domain and OU filtering** → *Sync selected domains and OUs*: tick exactly the synced OUs from the table above.
6. Uniquely identifying users: defaults. Filtering: *Synchronize all users and devices*. Optional features: **Password hash synchronization** only.
7. **Device options** → *Configure Hybrid Microsoft Entra join* → *Windows 10 or later domain-joined devices* → forest `corp.techcorp.example`, authentication service *Entra ID*, Enterprise Admin credentials (creates the SCP).
8. *Start the synchronization process when configuration completes* – ticked. Finish.
9. Remove `adm-eren.yeager` from Enterprise Admins.

## Verification

```powershell
# on TC-SYNC01
Get-ADSyncScheduler                         # SyncCycleEnabled True, 30-min cycle
Start-ADSyncSyncCycle -PolicyType Delta
Get-ADSyncConnectorRunStatus                # nothing running = finished
# anywhere, as the cloud admin
.\Test-TechCorpM365.ps1 -LabTenant -TenantDomain <tenant>.onmicrosoft.com   # Sync rows PASS
```

| Check | Expected |
|---|---|
| Entra admin center → Users | 20 users, *On-premises sync enabled = Yes*; no `adm-`/`wadm-` |
| Groups | `LIC_M365_BusinessPremium` (synced), no GG_/DL_ groups |
| Devices | Laptops in Workstations OUs appear as *Microsoft Entra hybrid joined* after their next sign-in |
| Change `title` on one AD user, delta sync | New title in Entra within one cycle |
| Entra Connect Health / *Sync errors* | 0 errors |

## Rollback

*Disable* sync (`Set-MsolDirSyncEnabled` is retired – use the Graph
`onPremisesSyncEnabled` organisation setting) only with a plan: users become
cloud-managed. Normally: fix the filtering and run a full sync
(`Start-ADSyncSyncCycle -PolicyType Initial`). **Deletion threshold** (500
objects by default) stops a mass delete; lower it to 50 for 20 users:
`Enable-ADSyncExportDeletionThreshold -DeletionThreshold 50`.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| User missing in Entra | OU not in scope / attribute error | *Synchronization Service Manager* → connector space search; sync errors in Entra admin center |
| User has `@<tenant>.onmicrosoft.com` UPN in production | UPN suffix not verified | Verify `techcorp.example`; UPN updates on next sync |
| Device stuck "Pending" | Computer object synced, device not yet registered | Sign in on the laptop / reboot; `dsregcmd /status` (SC-WIN-004) |
| Leaver's account vanished | Moved to an unsynced OU | M365-CHG-002, SC-M365-003 – restore from *Deleted users* within 30 days |
| "stopped-deletion-threshold-exceeded" | A filtering change would delete many objects | Check before you override: `Disable-ADSyncExportDeletionThreshold` once, intentionally |

## Evidence

`15-documentation/screenshots/phase-05/`: wizard summary page, Synchronization
Service Manager run history, Entra user list (sanitised), hybrid-joined device.

## References

- [Entra Connect Sync – custom installation](https://learn.microsoft.com/entra/identity/hybrid/connect/how-to-connect-install-custom)
- [Cloud Sync vs Connect Sync](https://learn.microsoft.com/entra/identity/hybrid/cloud-sync/what-is-cloud-sync#comparison-between-microsoft-entra-connect-and-cloud-sync)
- [Configure hybrid Microsoft Entra join](https://learn.microsoft.com/entra/identity/devices/how-to-hybrid-join)
