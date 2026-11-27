# OU Design

| Field | Value |
|---|---|
| Document ID | WIN-REF-001 |
| Owner | IT Specialist |
| Status | Approved design – lab build pending |
| Last reviewed | 2026-11-27 |
| Related requirements | BR-01, BR-14, BR-32 |
| Source data | [ou-structure.csv](ou-structure.csv) · [department-map.csv](department-map.csv) |

OUs exist for two reasons only: **linking Group Policy** and **delegating
administration**. They are not an org chart and they do not grant access to
data – groups do that ([groups-agdlp.md](groups-agdlp.md)).

## 1. Structure

```text
corp.techcorp.example
├── Builtin, Users, Computers ............ default containers – left empty (redircmp)
├── Domain Controllers ................... default OU – TC-DC01, TC-DC02
└── TechCorp
    ├── Users ............................ U- GPOs (drive maps, baseline, removable storage)
    │   ├── Management   (2)
    │   ├── Finance      (3)
    │   ├── HR           (2)
    │   ├── Sales        (5)
    │   ├── Development  (5)
    │   ├── Support      (2)
    │   └── IT           (1) ............. eren.yeager – the STANDARD account
    ├── Computers ........................ C-AllComputers-SecurityBaseline
    │   ├── Workstations ................. LAPS, BitLocker, local admins, user rights
    │   │   ├── Standard  (16) ........... Standard + Creative tier and spares; new joins land here
    │   │   ├── Developer  (5) ........... Developer tier (Docker/WSL2)
    │   │   └── IT         (1)
    │   └── Servers (1) .................. TC-FS01 – server LAPS and local admins
    ├── Groups
    │   ├── Role ......................... GG_ global groups ("who you are")
    │   └── Resource ..................... DL_ domain local groups ("what you can open")
    ├── Admin ............................ Domain Admins only – no GPOs linked
    │   ├── Accounts ..................... adm-eren.yeager, wadm-eren.yeager
    │   ├── Groups ....................... GG_IT_* admin role groups
    │   └── ServiceAccounts .............. svc- / gMSA (from Phase 10)
    └── Disabled ......................... leavers, 30 days – inheritance BLOCKED
```

Counts come from `Get-TechCorpAdPlan.ps1` (computers are placed by the
`DeviceTier` of the laptop's owner in [employees.csv](../../00-company-overview/data/employees.csv)).

## 2. Design rules and why

| Rule | Reason |
|---|---|
| One top-level `TechCorp` OU holds everything we create | Built-in containers can't have GPOs linked; one root makes "everything we manage" a single search base and a single delegation point |
| **Users and computers are never in the same OU** | User GPOs and computer GPOs are linked separately; mixing them is the #1 cause of "my GPO doesn't apply" (SC-WIN-003) |
| User OUs per **department** | Departments are how HR requests changes and how future delegation would be done ("HR may reset HR passwords") |
| Computer OUs per **device tier**, not department | Hot-desking: a laptop belongs to a person, not a department; what differs between laptops is the *policy* (developers need Hyper-V/WSL2) |
| `Admin` OU separate from `Users` | Privileged accounts must not receive user GPOs (drive maps, etc.) and must not be manageable by any delegated helpdesk role |
| `Disabled` OU with **inheritance blocked** | A leaver's account gets no policy, no drive maps; the 30-day retention is easy to see |
| Every OU is *protected from accidental deletion* | Deleting an OU deletes everything in it |
| OU names are single words, no spaces or `&` | No escaping in DNs and scripts ("Sales & Marketing" → `Sales`, change WIN-CHG-003) |
| Depth ≤ 4 levels | Easier to read in ADUC and in `gpresult` |

## 3. Delegation

| Who | Where | Rights | How |
|---|---|---|---|
| Domain Admins (`adm-eren.yeager`) | Whole domain | Full | Built-in |
| `GG_IT_HelpdeskOperators` (`wadm-eren.yeager`) | `TechCorp/Users` and below, user objects | Reset password, force change at next logon, unlock | `dsacls` in `Deploy-TechCorpAd.ps1` step 7 |
| `GG_IT_WorkstationAdmins` (`wadm-eren.yeager`) | `TechCorp/Computers/Workstations` and below | Create / delete computer objects (domain join with `ms-DS-MachineAccountQuota = 0`); read/reset LAPS passwords | `dsacls` + `Set-LapsADReadPasswordPermission` |
| Standard users | – | **Cannot** join computers (quota set to 0) | `Deploy-TechCorpAd.ps1` step 9 |

In a one-person IT department the helpdesk group has one member today; it
exists so that a second IT person or an MSP can be given exactly these rights
without becoming a Domain Admin.

Verify delegation: *ADUC → OU → Properties → Security → Advanced* or
`(Get-Acl "AD:OU=Users,OU=TechCorp,DC=corp,DC=techcorp,DC=example").Access | Where-Object IdentityReference -like '*Helpdesk*'`.

## 4. Change process

1. Edit [ou-structure.csv](ou-structure.csv) (and [department-map.csv](department-map.csv) for a new department).
2. `Get-TechCorpAdPlan.ps1 -SelfTest` (also runs in CI on every push).
3. `Deploy-TechCorpAd.ps1 -WhatIf`, review, run.
4. Link GPOs if the new OU needs them ([gpo-design.md](../group-policy/gpo-design.md)).

Moving an object between OUs changes which GPOs apply to it – check with
`gpresult` after the next refresh.
