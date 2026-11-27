# SC-M365-001: New starter has no mailbox on day 1

| Field | Value |
|---|---|
| Scenario ID | SC-M365-001 |
| Category | Microsoft 365 |
| Difficulty | ⭐⭐ |
| Priority (if real) | P2 – new starter cannot work (BR-10) |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | Lab tenant + lab AD with Entra Connect |

## 1. The report

> *"The new account executive can sign in to his laptop, but Outlook says there's no mailbox and Office says 'unlicensed product'."* – Jean Kirstein

## 2. Environment / context

New employee added to `employees.csv`, `Deploy-TechCorpAd.ps1` run, sync completed. The IT Specialist skipped `Deploy-TechCorpM365.ps1` ("the licence comes from the group anyway").

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

Create a test user in `TechCorp/Users/Sales`, add it to `LIC_M365_BusinessPremium`, sync – and do not set `usageLocation`.

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Is the user in the cloud? | Entra admin center → Users | Yes, synced | Sync fine |
| 2 | Licence | User → *Licenses* | Business Premium **assigned via group – Error** | Group licensing failed for this user |
| 3 | Error detail | `Get-MgUser -UserId <upn> -Property LicenseAssignmentStates \| Select -Expand LicenseAssignmentStates` | State *Error*, error *usage location not set* | Root cause |
| 4 | Group view | Group → *Licenses* → "1 user with errors" | Same user | Confirms |
| 5 | Alternative causes ruled out | Seats available (`Get-MgSubscribedSku`) | Seats free | Not a seat shortage |

## 5. Root cause

Synced accounts have no usage location; Microsoft cannot assign a licence
without knowing which country's service terms apply.

## 6. Resolution

`Deploy-TechCorpM365.ps1 -Skip Mail,Teams,SharePoint` (sets `GR`), or
`Update-MgUser -UserId <upn> -UsageLocation GR`. Group licensing retries
automatically (or *Reprocess* on the group's licence page). Mailbox is
created within minutes.

## 7. Verification

`Test-TechCorpM365.ps1` Licensing row for the user: *Active*, assigned by group; Outlook opens the mailbox.

## 8. Prevention

The joiner checklist ([licensing-and-lifecycle.md §2](../../05-microsoft-365/user-management/licensing-and-lifecycle.md#2-joiner))
runs the M365 deploy step; the Phase 8 onboarding script will do both in one go.

## 9. Skills practised

- Group-based licensing states and errors
- Reading user properties with Microsoft Graph PowerShell
