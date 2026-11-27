# Build and Verify the Group Policy Objects

| Field | Value |
|---|---|
| Document ID | WIN-PRC-005 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved after the first lab build |
| Last reviewed | 2026-11-27 |
| Related requirements | BR-03, BR-12, BR-14, BR-18, BR-26 |

## Purpose

Create every GPO in the [design](gpo-design.md): the scripted part with
`Deploy-TechCorpGpo.ps1`, the rest in the Group Policy Management Console
(GPMC), then prove each one applies with `gpresult`.

## Prerequisites

- [ ] OUs, groups and admin accounts exist (`Deploy-TechCorpAd.ps1`)
- [ ] Signed in to TC-DC01 (or the IT laptop with RSAT) as `adm-eren.yeager`
- [ ] A domain-joined lab client `TC-LT-LAB01` in `TechCorp/Computers/Workstations/Standard` and a test user (e.g. `nile.dok`) for verification

## Procedure

### 1. Central store for ADMX templates

So every admin edits GPOs with the same, current templates:

```powershell
$store = '\\corp.techcorp.example\SYSVOL\corp.techcorp.example\Policies\PolicyDefinitions'
Copy-Item "$env:SystemRoot\PolicyDefinitions" -Destination $store -Recurse
```

Later, copy newer Windows 11 / Microsoft 365 ADMX files into the same folder.
GPMC shows *Administrative Templates: Policy definitions (ADMX files) retrieved from the central store*.

### 2. Scripted GPOs

```powershell
cd C:\Lab\techcorp-it-operations-lab\07-powershell\active-directory
.\Deploy-TechCorpGpo.ps1 -WhatIf          # review: create, link, filter, set
.\Deploy-TechCorpGpo.ps1 -PrepareLaps     # LAPS schema + permissions the first time
```

*Expected result:* the 11 non-default GPOs exist and are linked;
`C-AllComputers-SecurityBaseline`, both LAPS GPOs, BitLocker, `U-AllUsers-Baseline`
and `U-FinanceHR-RemovableStorage` contain their settings (check *Settings*
tab in GPMC); `U-FinanceHR-RemovableStorage` shows `GG_Finance_Users` and
`GG_HR_Users` under *Security Filtering* and Authenticated Users with *Read*
on the *Delegation* tab.

### 3. Default Domain Policy – password and lockout

GPMC → *Default Domain Policy* → Edit → *Computer Configuration → Policies →
Windows Settings → Security Settings → Account Policies*: set the values from
[user-accounts.md §3](../users-and-groups/user-accounts.md#3-password-and-lockout-policy).
Then on TC-DC01: `gpupdate /force` and `Get-ADDefaultDomainPasswordPolicy`.

### 4. `C-DomainControllers-Audit`

*Computer Configuration → Policies → Windows Settings → Security Settings →
Advanced Audit Policy Configuration → Audit Policies*:

| Category | Subcategory | Audit |
|---|---|---|
| Account Logon | Credential Validation, Kerberos Authentication Service, Kerberos Service Ticket Operations | Success, Failure |
| Account Management | User Account Management, Security Group Management, Computer Account Management | Success, Failure |
| DS Access | Directory Service Changes | Success |
| Logon/Logoff | Logon, Account Lockout | Success, Failure |
| Policy Change | Audit Policy Change, Authentication Policy Change | Success |
| Privilege Use | Sensitive Privilege Use | Failure |

Plus *Security Options → Audit: Force audit policy subcategory settings … to
override audit policy category settings* = Enabled, and *Event Log → Maximum
security log size* = 1048576 KB. Verify on the DC: `auditpol /get /category:*`.

### 5. `C-Workstations-LocalAdmins` and `C-Servers-LocalAdmins`

*Computer Configuration → Preferences → Control Panel Settings → Local Users
and Groups → New → Local Group*:

- Action **Update**, Group name **Administrators (built-in)**
- Tick **Delete all member users** and **Delete all member groups**
- Members: `TECHCORP\GG_IT_WorkstationAdmins` (servers: `TECHCORP\Domain Admins`, `TECHCORP\GG_IT_ServerAdmins`)

The built-in local Administrator is not removed by "delete all members" – it
stays, managed by LAPS. Verify on the client: `net localgroup Administrators`.

### 6. `C-Workstations-UserRights`

*Computer Configuration → Policies → Windows Settings → Security Settings →
Local Policies → User Rights Assignment*: add `TECHCORP\Domain Admins`,
`TECHCORP\Enterprise Admins`, `TECHCORP\Schema Admins` to

- Deny log on locally
- Deny log on through Remote Desktop Services
- Deny log on as a batch job
- Deny log on as a service

Test: sign in to `TC-LT-LAB01` as `adm-eren.yeager` → *"The sign-in method you're trying to use isn't allowed"*. `wadm-eren.yeager` signs in fine.

### 7. `U-AllUsers-DriveMappings`

*User Configuration → Preferences → Windows Settings → Drive Maps → New →
Mapped Drive*, one item per row of the [drive table](gpo-design.md#4-drive-mappings-u-allusers-drivemappings):

1. *General*: Action **Update**, Location = DFS path, *Reconnect*, Label, drive letter.
2. *Common*: tick **Item-level targeting** → *Targeting…* → *New Item → Security Group* → the `GG_` group, *User in group*.
3. Order: S:, then the T: items, then M:, P:, I:.

### 8. Back up

```powershell
New-Item -ItemType Directory -Force C:\GPOBackup | Out-Null
Backup-GPO -All -Path C:\GPOBackup -Comment "M5 baseline $(Get-Date -Format yyyy-MM-dd)"
Get-GPOReport -All -ReportType Html -Path C:\GPOBackup\all-gpos.html
```

Copy off the DC (NAS, Phase 10). The HTML report is the evidence for this step.

## Verification

On `TC-LT-LAB01` signed in as `nile.dok` (Finance):

```powershell
gpupdate /force
gpresult /r /scope computer      # C-AllComputers-SecurityBaseline, C-Workstations-* applied
gpresult /r /scope user          # U-AllUsers-*, U-FinanceHR-RemovableStorage applied
gpresult /h $env:TEMP\gp.html    # full report - attach to evidence
Get-PSDrive -PSProvider FileSystem   # S: and T: (Finance) - no M:, P:, I:
Get-LapsADPassword -Identity TC-LT-LAB01 -AsPlainText   # as wadm-: password returned
manage-bde -status C:            # once BitLocker is turned on (Phase 4)
```

| Test | Expected |
|---|---|
| LLMNR off: `Get-ItemProperty 'HKLM:\Software\Policies\Microsoft\Windows NT\DNSClient'` | `EnableMulticast : 0` |
| Copy a file to a USB stick as `nile.dok` | *You need permission to perform this action* |
| Same as `connie.springer` (Sales) | Works – the GPO is filtered to Finance/HR |
| Idle 10 minutes | Screen locks |
| `adm-eren.yeager` signs in to the laptop | Refused |
| `Test-TechCorpAd.ps1` | GPO checks PASS |

## Rollback

- One GPO misbehaving: disable its **link** (`Set-GPLink -Name <gpo> -Target <ou> -LinkEnabled No`) – instant and reversible; don't delete it.
- Bad edit: `Restore-GPO -Name <gpo> -Path C:\GPOBackup`.
- Clients keep some settings after the GPO is removed ("tattooing" of non-policy registry keys, e.g. `LmCompatibilityLevel`) – set the opposite value explicitly if a rollback is needed.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| GPO not in `gpresult` at all | Linked to the wrong OU / object in the wrong OU | `Get-GPInheritance -Target <ou>`; move the object (SC-WIN-003) |
| Listed under *filtered out – Denied (Security)* | Not in the filtering group, or Authenticated Users lost Read | Delegation tab (SC-WIN-002) |
| Drive map missing for one user | Targeting group wrong / user not re-logged after group change | GPP targeting; log off/on |
| User part of GPO applies only after logoff | Drive maps and some CSEs process at logon in the foreground | Expected; `gpupdate /force` asks to log off |
| Event 1058 / 1030 | Client can't read SYSVOL – DNS or DFS-R problem | `\\corp.techcorp.example\SYSVOL` reachable? `dcdiag /test:sysvolcheck` |
| LAPS password never appears in AD | Schema not extended / self-permission missing / GPO not applied | `-PrepareLaps`; event log *Microsoft-Windows-LAPS/Operational* |

## Evidence

`15-documentation/screenshots/phase-03/`: GPMC tree with links, `gpresult /h`
reports for one Finance and one Sales user, USB-write denial, `Get-GPOReport` HTML.

## References

- [Group Policy processing](https://learn.microsoft.com/previous-versions/windows/desktop/policy/group-policy-hierarchy)
- [MS16-072 security filtering change](https://support.microsoft.com/kb/3159398)
- [Windows LAPS](https://learn.microsoft.com/windows-server/identity/laps/laps-overview)
- [Advanced audit policy recommendations](https://learn.microsoft.com/windows-server/identity/ad-ds/plan/security-best-practices/audit-policy-recommendations)
