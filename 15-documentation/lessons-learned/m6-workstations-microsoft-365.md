# Lessons Learned: Milestone 6 – Workstations and Microsoft 365

| Field | Value |
|---|---|
| Document ID | DOC-LL-003 |
| Related phase / scenario | Phases 4–5 (M6), SC-M365-003, SC-WIN-004 |
| Date | 2026-11-27 |

## What happened

Designed the laptop build (clean install, domain join, hybrid Entra join,
BitLocker, software from a catalogue) and the Microsoft 365 tenant (admins,
Entra Connect, licensing, Exchange Online, Teams, SharePoint/OneDrive). The
M5 pattern was reused: CSVs as the design, an offline plan with a CI
self-test, idempotent deploy scripts and read-only verification scripts.

## What went well

- The M5 data paid off: `employees.csv` already decides each laptop's OU,
  each user's software, their licence and their Teams membership (through the
  synced `department` attribute and dynamic groups).
- Validating sharing levels and guest access in CI turns BR-26 ("HR and
  Finance data stays inside") into a test instead of a sentence.

## What went wrong / was harder than expected

| Problem | Found when | Change |
|---|---|---|
| The leavers' OU was outside the sync scope – leaving scope *deletes* the cloud account and mailbox | Writing the leaver steps | **M365-CHG-002** – `Disabled` synced; CI enforces it |
| Scan-to-e-mail on SMTP AUTH 587 relies on basic authentication being retired, and a mailbox password in the printer | Writing the Exchange procedure | **M365-CHG-001** – inbound connector on port 25, firewall rule and SPF updated |
| Direct IP printing needs admin rights for drivers and can't keep TC-PRN02 Finance-only | Writing the printer procedure | **END-CHG-001** – print server on TC-FS01 |
| Group-based licensing ignores nested groups | Designing the licence group | `LIC_` group with direct members; CI rule |
| Synced users have no usage location → licence error | Researching licensing | Set by the deploy script (SC-M365-001) |
| The UPN suffix `techcorp.example` was used in M5 but never registered in the forest | Entra Connect prerequisites | `Deploy-TechCorpAd.ps1` step 0 |
| `techcorp.example` can never be verified in a real tenant | Planning the lab | `-LabTenant` switch on every M365 script; DNS/DKIM/connector marked production-only |
| The Entra Connect server is Tier 0 and shouldn't share the file server | Choosing where to install | New VM TC-SYNC01 (fits the existing Server licences); lab installs on TC-DC01 |
| A tenant-specific value (tenant ID) inside a GPO setting | OneDrive KFM | `{{TenantId}}` placeholder resolved by `Deploy-TechCorpGpo.ps1 -TenantId` |

## What I learned (technical)

- Hybrid join = domain join + computer object synced + SCP + registration at sign-in; `dsregcmd /status` shows each part.
- Sync scope is a delete switch: anything leaving it is deleted in the cloud.
- Dynamic groups remove membership maintenance but make the HR attribute critical (SC-M365-004).
- Full Access through a group disables Outlook auto-mapping (SC-M365-005).
- Suspend BitLocker before firmware updates, or the TPM won't release the key (SC-HW-001).

## What I will do differently

| Action | Where it is documented | Done |
|---|---|---|
| Check every "leaver" path for what gets *deleted*, not only what gets *disabled* | licensing-and-lifecycle.md §4 | ☑ |
| Keep tenant-specific values out of the repo (placeholders + parameters) | gpo-registry-settings.csv | ☑ |
| Build the lab tenant and run the M5 + M6 labs inside one trial window | tenant-setup.md | ☐ |
| Move to Intune/Autopilot and Conditional Access | M7 | ☐ |
