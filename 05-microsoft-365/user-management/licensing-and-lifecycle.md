# Licensing and the Cloud Side of Joiners, Movers and Leavers

| Field | Value |
|---|---|
| Document ID | M365-PRC-003 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved after the lab tenant is built |
| Last reviewed | 2026-11-27 |
| Related requirements | BR-01, BR-10, BR-26, BR-27 |

## 1. Licensing

| Item | Value |
|---|---|
| SKU | Microsoft 365 Business Premium (`SPB`) × 20 |
| Assigned by | **Group-based licensing** on `LIC_M365_BusinessPremium` (synced from `TechCorp/Groups/Licensing`) |
| Members | Every employee **directly** (`@employees` in [ad-groups.csv](../../03-windows-server/users-and-groups/ad-groups.csv)) |
| Usage location | `GR` – set on every user by `Deploy-TechCorpM365.ps1` |
| Not licensed | Break-glass and admin accounts, shared mailboxes (< 50 GB, no archive), room mailboxes (Teams Rooms Basic instead) |

Two rules that bite – both enforced in CI by `Get-TechCorpAdPlan.ps1 -SelfTest`:

1. **No nesting.** Entra group-based licensing does not apply to members of a
   nested group, so `LIC_M365_BusinessPremium` contains user accounts, not
   `GG_All_Staff`.
2. **Usage location is mandatory.** Synced users arrive without one, and a
   licence cannot be assigned until it is set – the group shows the user in
   *error* state (SC-M365-001).

A new hire beyond 20 needs a purchased seat first: the group then shows
*"Not enough licences"* for that user (`Get-MgUser -Property LicenseAssignmentStates`).

## 2. Joiner

Cloud steps, after the AD steps in
[user-accounts.md §4](../../03-windows-server/users-and-groups/user-accounts.md#4-account-lifecycle-automated-in-m8).

| # | What happens | Who / how | Time |
|---|---|---|---|
| 1 | Account syncs to Entra ID | Entra Connect delta sync | ≤ 30 min (`Start-ADSyncSyncCycle -PolicyType Delta` to hurry) |
| 2 | Usage location + licence | `Deploy-TechCorpM365.ps1 -Skip Mail,Teams,SharePoint` | minutes |
| 3 | Mailbox, OneDrive, Teams access | Automatic with the licence | ≤ 1 h |
| 4 | Department team + company team | Dynamic groups (department attribute) | ≤ 24 h, usually minutes |
| 5 | Shared mailbox access if the role needs it | Add the user in [mailboxes.csv](../exchange-online/mailboxes.csv) → deploy | minutes |
| 6 | MFA registration on day 1 | User, with IT, at handover (security defaults prompt) | 5 min |

## 3. Mover

Change the department in `employees.csv` → `Deploy-TechCorpAd.ps1` → sync.
The dynamic rules move the person to the new team automatically; shared
mailbox permissions come from `mailboxes.csv` and are reviewed in the same ticket.

## 4. Leaver (same day – BR-10)

Order matters (M365-CHG-002):

1. **Block now** – AD: `Disable-ADAccount` (syncs as *sign-in blocked*); in
   Entra *Revoke sessions* (`Revoke-MgUserSignInSession -UserId <upn>`) so
   existing tokens stop working without waiting for expiry.
2. **Mailbox** – convert to shared so the manager keeps access without a licence:
   `Set-Mailbox <upn> -Type Shared`; `Add-MailboxPermission <upn> -User <manager> -AccessRights FullAccess`;
   out-of-office reply naming the new contact.
3. **OneDrive** – *Microsoft 365 admin center → user → OneDrive → Get access to files* for the manager; move what is needed into the department site within 30 days.
4. **Licence** – remove the user from `LIC_M365_BusinessPremium` (ad-groups.csv uses `@employees`, so deleting the row from `employees.csv` does it on the next deploy).
5. **Move to `TechCorp/Disabled`** – still synced, so nothing is deleted.
6. **After 30 days** – delete the AD account → the cloud account goes to *Deleted users* (30 more days). The shared mailbox remains until the manager confirms it can go.

Devices: collect the laptop, rebuild ([laptop-build.md](../../04-endpoint-management/windows-11/laptop-build.md)).

## Verification

`Test-TechCorpM365.ps1` *Licensing* rows: every user *Active*, assigned by
group, no errors. For a leaver: user *Blocked*, mailbox type *Shared*, no
licence.
