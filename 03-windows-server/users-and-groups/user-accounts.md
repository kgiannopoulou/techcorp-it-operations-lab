# User Accounts, Admin Accounts and Password Policy

| Field | Value |
|---|---|
| Document ID | WIN-PRC-004 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved after the first lab build |
| Last reviewed | 2026-11-27 |
| Related requirements | BR-01, BR-10, BR-11, BR-14, BR-26 |
| Source data | [employees.csv](../../00-company-overview/data/employees.csv) · [admin-accounts.csv](admin-accounts.csv) |

## 1. Standard user accounts

Created by [Deploy-TechCorpAd.ps1](../../07-powershell/active-directory/Deploy-TechCorpAd.ps1)
from `employees.csv` – one row, one account, no manual typing.

| Attribute | Source / value | Example (E006) |
|---|---|---|
| `sAMAccountName` | `Username` (≤ 20 chars, CI-checked) | `historia.reiss` |
| `userPrincipalName`, `mail` | `<Username>@techcorp.example` – same as e-mail (BR-01) | `historia.reiss@techcorp.example` |
| `givenName`, `sn`, `displayName`, `cn` | `FirstName`, `LastName` | Historia Reiss |
| `employeeID` | `EmployeeID` | E006 |
| `department`, `title` | `Department`, `JobTitle` | Human Resources, HR Manager |
| `manager` | `Manager` (resolved to the manager's DN) | hange.zoe |
| `company`, `physicalDeliveryOfficeName` | constants | TechCorp Solutions, Athens HQ |
| OU | `department-map.csv` → `TechCorp/Users/<Code>` | `TechCorp/Users/HR` |
| Groups | Department role group (+ manager/payroll groups) from `ad-groups.csv` | GG_HR_Users, GG_All_Managers |

These attributes are not decoration: Entra Connect (Phase 5) copies them to
Microsoft 365, so the Teams/Outlook directory and org chart come from here.

### First password

- New accounts get a one-time password passed to `-InitialPassword` (never
  written to disk, a CSV or a ticket) and *User must change password at next
  logon* is set.
- The one-time password is given to the new starter **in person or by phone**
  on day 1, never by e-mail (the mailbox isn't theirs yet) – BR-10.

## 2. Privileged accounts – design change WIN-CHG-001

The naming standard originally had one admin account per IT person
(`adm-firstname.lastname`). Writing the GPO procedures showed the problem: the
same account would be a **Domain Admin** *and* the account used to sign in to
users' laptops for support. A laptop is the most exposed machine in the
company; credentials typed or cached there can be stolen and replayed against
the DCs.

**WIN-CHG-001 – split privileged accounts by tier:**

| Account | Tier | Member of | May sign in to | Must never sign in to |
|---|---|---|---|---|
| `eren.yeager` | User | GG_IT_Users | Own laptop, M365, e-mail | Servers, other laptops as admin |
| `wadm-eren.yeager` | Workstations | GG_IT_WorkstationAdmins, GG_IT_HelpdeskOperators, GG_IT_AdminAccounts | Laptops (support, domain join), ADUC for password resets | DCs, file server |
| `adm-eren.yeager` | Servers / DCs | Domain Admins, GG_IT_ServerAdmins, GG_IT_AdminAccounts, Protected Users | DCs, TC-FS01, RSAT on the IT laptop | **Laptops** – blocked by `C-Workstations-UserRights` |
| `Administrator` (built-in) | Break-glass | Domain Admins | DCs, only when adm- is unusable | Everything else; use is reported to the Operations Manager |

Hardening applied to both admin accounts: *Account is sensitive and cannot be
delegated*, UPN in the AD domain (`@corp.techcorp.example` – never synced to
Microsoft 365, no mailbox), stronger password policy (`PSO-AdminAccounts`).
`adm-` is also in **Protected Users** (no NTLM, no cached credentials, no
delegation, 4-hour tickets). The built-in Administrator is **not** in
Protected Users on purpose – it must still work if Kerberos is broken.

Laptop support uses the laptop's **LAPS** local Administrator password
(readable by `GG_IT_WorkstationAdmins`, rotated automatically after use).

## 3. Password and lockout policy

### Domain default – edited in the *Default Domain Policy* GPO

| Setting | Value | Reason |
|---|---|---|
| Minimum password length | **14** | Length beats complexity; 14 is the classic maximum of this setting (more needs *Relax minimum password length limits*) |
| Complexity | Enabled | Blocks the worst passwords until Entra Password Protection (Phase 6) |
| Password history | 24 | No re-using the previous password |
| Maximum age | **0 – never expires** | NIST SP 800-63B: forced periodic changes lead to `Spring2027!` → `Summer2027!`. Change only on suspicion of compromise. Compensated by MFA (BR-11), lockout and the length |
| Minimum age | 1 day | Stops cycling through the history in one go |
| Lockout threshold | 10 invalid attempts | Stops online guessing without locking people out for one typo |
| Lockout duration / reset counter after | 15 min / 15 min | Self-healing – no helpdesk call needed for an accidental lockout |
| Store passwords with reversible encryption | Disabled | – |

> The domain password policy **must** be edited in the *Default Domain Policy*
> GPO (*Computer Configuration → Policies → Windows Settings → Security
> Settings → Account Policies*). `Set-ADDefaultDomainPasswordPolicy` writes
> the domain object directly, and the next time the DCs apply the Default
> Domain Policy the GPO's values overwrite it. `Test-TechCorpAd.ps1` reads the
> result with `Get-ADDefaultDomainPasswordPolicy`.

### Fine-grained policy for privileged accounts – `PSO-AdminAccounts`

Created by `Deploy-TechCorpAd.ps1`, applied to `GG_IT_AdminAccounts`, precedence 10.

| Setting | Value |
|---|---|
| Minimum length | 20 (password manager generated) |
| Complexity / history | On / 24 |
| Maximum age | 365 days |
| Lockout | 5 attempts, 30 min |

Check what applies to an account: `Get-ADUserResultantPasswordPolicy adm-eren.yeager`.

## 4. Account lifecycle (manual now, automated in Phase 8)

### Joiner

1. HR request with start date, department, title, manager (BR-10).
2. Add the row to `employees.csv` (and laptop to `hardware-inventory.csv`), push – CI validates.
3. `Deploy-TechCorpAd.ps1 -InitialPassword (Read-Host -AsSecureString)` – creates the account in the right OU and groups.
4. Day 1: give the one-time password in person; user sets their own at first sign-in.

### Mover (department change)

1. Change `Department` / `JobTitle` / `Manager` in `employees.csv`.
2. `Deploy-TechCorpAd.ps1` moves the account to the new OU, updates attributes and **adds** the new department group.
3. The old department group membership is reported as `WARN unexpected member` – after the handover period agreed with both managers, run with `-RemoveUnexpectedMembers`.

### Leaver (same day – BR-10)

```powershell
$u = 'connie.springer'
Disable-ADAccount $u
Set-ADAccountPassword $u -Reset -NewPassword (Read-Host -AsSecureString 'Random one-time value')
$groups = (Get-ADPrincipalGroupMembership $u | Where-Object Name -ne 'Domain Users').Name
Set-ADUser $u -Description "Left $(Get-Date -Format yyyy-MM-dd); groups: $($groups -join ', ')"
$groups | ForEach-Object { Remove-ADGroupMember $_ -Members $u -Confirm:$false }
Get-ADUser $u | Move-ADObject -TargetPath 'OU=Disabled,OU=TechCorp,DC=corp,DC=techcorp,DC=example'
```

Then remove the row from `employees.csv` (git history keeps the record) and
delete the account after 30 days (still restorable from the Recycle Bin).
**Before** moving the account, do the cloud steps (revoke sessions, mailbox →
shared, OneDrive access for the manager) in
[licensing-and-lifecycle.md §4](../../05-microsoft-365/user-management/licensing-and-lifecycle.md#4-leaver-same-day--br-10).
The Disabled OU is synced (M365-CHG-002), so the cloud account is blocked, not deleted.

## 5. Service accounts (from Phase 10)

Prefer **group Managed Service Accounts** (gMSA – AD rotates a 240-character
password) over `svc-` accounts with a password someone has to remember. A
gMSA needs the KDS root key once per forest:

```powershell
Add-KdsRootKey -EffectiveImmediately   # usable after AD replication (~10 h in production)
```

## Verification

```powershell
Get-ADUser -SearchBase 'OU=Users,OU=TechCorp,DC=corp,DC=techcorp,DC=example' -Filter * |
    Measure-Object                                         # 20
Get-ADGroupMember 'Domain Admins' | Select-Object SamAccountName   # Administrator, adm-eren.yeager
Get-ADUserResultantPasswordPolicy wadm-eren.yeager         # PSO-AdminAccounts
Get-ADDefaultDomainPasswordPolicy                          # 14 / 24 / 0 / 10
.\Test-TechCorpAd.ps1                                      # User + Admin checks PASS
```

## Rollback

Accounts created by mistake: delete (Recycle Bin keeps them 180 days). A wrong
bulk change: fix the CSV and run the deploy script again – it converges.
