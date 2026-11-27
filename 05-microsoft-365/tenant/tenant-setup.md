# Microsoft 365 Tenant Setup and Admin Accounts

| Field | Value |
|---|---|
| Document ID | M365-PRC-001 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved after the lab tenant is built |
| Last reviewed | 2026-11-27 |
| Related requirements | BR-01, BR-02, BR-11, BR-26, BR-27 |
| Source data | [cloud-admins.csv](cloud-admins.csv) |

## Purpose

Create the Microsoft 365 Business Premium tenant, its administrators and the
organisation-wide settings that everything else in `05-microsoft-365` builds on.

## Tenant facts

| Item | Production | Lab |
|---|---|---|
| Licence | Microsoft 365 Business Premium × 20 (`SPB`) | Business Premium **trial** (time-limited) or an M365 developer sandbox if available to you |
| Initial domain | `techcorpsolutions.onmicrosoft.com` | `<random>.onmicrosoft.com` – pass it as `-TenantDomain` to every script |
| Custom domain | `techcorp.example` (verified via TXT) | **Cannot be verified** – `.example` is reserved (RFC 2606). Lab uses the onmicrosoft domain: `-LabTenant` |
| Data location | EU (chosen by the billing country at sign-up – Greece) | Same |
| Users | Synced from AD (Entra Connect) | Synced from the lab AD |

> **Lab rule:** only fictional employees from `employees.csv` ever go into the
> lab tenant. Do the M365 lab sessions inside the trial window and capture
> evidence as you go – an expired trial cannot be "re-run" later.

## Admin model

| Account | Type | Roles | Sign-in |
|---|---|---|---|
| `bg-admin01@…onmicrosoft.com` | Break-glass | Global Administrator | FIDO2 key in the office safe + long password in a sealed envelope |
| `bg-admin02@…onmicrosoft.com` | Break-glass | Global Administrator | Second FIDO2 key held off-site by the CEO |
| `adm-eren.yeager@…onmicrosoft.com` | Daily cloud admin | User, License, Groups, Exchange, Teams, SharePoint, Hybrid Identity Administrator + Global Reader | Authenticator app (phishing-resistant method in M7) |
| `eren.yeager@techcorp.example` | Normal user (synced) | none | Normal staff sign-in |

Rules (checked by `Get-TechCorpM365Plan.ps1 -SelfTest`):

- Admin accounts are **cloud-only** on the onmicrosoft domain – if AD is compromised, the attacker does not own the tenant. On-prem `adm-`/`wadm-` accounts are never synced (Admin OU out of sync scope).
- Exactly **two** break-glass accounts; Global Administrator is held **only** by them (2–4 GAs in total).
- No admin account has a licence (no mailbox to phish, no apps).
- Break-glass sign-ins raise an alert (M7: Conditional Access exclusion + alert rule).

## Procedure

1. **Sign up** for Business Premium (lab: trial) with country *Greece*; the
   first account becomes `bg-admin01`. Note the tenant ID
   (*Entra admin center → Overview*) – needed for OneDrive Known Folder Move
   (`Deploy-TechCorpGpo.ps1 -TenantId`).
2. **Second break-glass and daily admin** (*Microsoft 365 admin center → Users → Add a user*):
   `bg-admin02` (Global Administrator) and `adm-eren.yeager` (roles from the
   table, assigned in *Entra admin center → Roles & admins*). No licences.
   Register FIDO2 keys for both break-glass accounts.
3. **Security defaults stay ON** until Conditional Access replaces them in M7.
   They enforce MFA registration for everyone and MFA for admins – the gap
   between "users exist in the cloud" and "Conditional Access exists" is not
   left unprotected (BR-11).
4. **Add the domain** (production only): *Settings → Domains → Add domain* →
   `techcorp.example`, publish the TXT verification record, then the records in
   [dns-design.md §4](../../02-network-infrastructure/dns/dns-design.md#4-public-dns-records-microsoft-365)
   **after** mailboxes are ready (MX cut-over is the e-mail go-live).
5. **Organisation settings**: *Org settings → Organization profile* – name
   *TechCorp Solutions*, technical contact `it@` → the IT Specialist;
   *Release preferences* – **Targeted release for selected users** (IT +
   Operations Manager see changes a few weeks early); *Customer lockbox* off
   (not in BP); *Audit* – confirm unified audit log is on
   (`Get-AdminAuditLogConfig | Select UnifiedAuditLogIngestionEnabled`).
6. **Users cannot create tenants or app registrations** (*Entra admin center →
   Users → User settings*): *Users can register applications* = No;
   *Restrict non-admin users from creating tenants* = Yes;
   *Users can create security groups / M365 groups* = No (all groups come from teams.csv).
7. **Guest settings** (*External Identities → External collaboration settings*):
   guests have limited access; *Only users assigned to specific admin roles
   can invite* – invitations go through IT; Sales' team allows guests (teams.csv).

## Verification

```powershell
Connect-MgGraph -Scopes 'Directory.Read.All', 'RoleManagement.Read.Directory'
.\Test-TechCorpM365.ps1 -LabTenant -TenantDomain <tenant>.onmicrosoft.com   # Admins rows PASS
```

Sign in as each break-glass account once (from the IT laptop) to prove the
keys work; record the date on the envelope.

## Rollback

Admin accounts and settings are reversible in the admin centres. A trial
tenant can be deleted after the lab (*Settings → Org settings → Organization
profile*); export the evidence first.

## References

- [Emergency access accounts](https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access)
- [Security defaults](https://learn.microsoft.com/entra/fundamentals/security-defaults)
- [Least-privileged roles by task](https://learn.microsoft.com/entra/identity/role-based-access-control/delegate-by-task)
