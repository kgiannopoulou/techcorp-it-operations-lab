# SC-M365-003: A leaver's mailbox disappeared overnight

| Field | Value |
|---|---|
| Scenario ID | SC-M365-003 |
| Category | Microsoft 365 |
| Difficulty | ⭐⭐⭐ |
| Priority (if real) | P2 – client e-mails and handover data at risk |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | Lab AD + Entra Connect + lab tenant |

## 1. The report

> *"Bertolt left yesterday. I was supposed to get access to his mailbox for his client threads – today it doesn't exist."* – Jean Kirstein

## 2. Environment / context

Yesterday the leaver's AD account was disabled and moved to `TechCorp/Disabled`. A new admin had unticked that OU in Entra Connect ("leavers don't need to be in the cloud").

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

Untick `TechCorp/Disabled` in Entra Connect OU filtering, then move a test user into it and run a delta sync.

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | User in Entra | Entra admin center → Users | Not in active users | Deleted, not blocked |
| 2 | Deleted users | *Deleted users* / `Get-MgDirectoryDeletedItemAsUser` | User there, deleted by *On-Premises Directory Synchronization Service Account* | Sync deleted it |
| 3 | Why | Sync Service Manager → *Export* run → deletes; OU filtering | `Disabled` unticked | Leaving sync scope = delete |
| 4 | Mailbox | `Get-Mailbox -SoftDeletedMailbox` | Soft-deleted mailbox | Recoverable within 30 days |
| 5 | Design | `ou-structure.csv` | `Disabled` = Yes (M365-CHG-002) | Server drifted from the design |

## 5. Root cause

An object leaving the sync scope is treated as deleted on-prem, so the cloud
user (and with it the mailbox and OneDrive) is soft-deleted.

## 6. Resolution

1. Re-tick `TechCorp/Disabled`, delta sync – the connector matches the soft-deleted user back (`ms-DS-ConsistencyGuid`), restoring it; or restore from *Deleted users* first.
2. Continue the leaver procedure properly: mailbox → shared, Full Access for the manager, licence removed ([licensing-and-lifecycle.md §4](../../05-microsoft-365/user-management/licensing-and-lifecycle.md#4-leaver-same-day--br-10)).

## 7. Verification

User back as *blocked*; mailbox of type *Shared*, manager has access; client threads present.

## 8. Prevention

- M365-CHG-002 documented, `EntraSync` rules enforced in CI.
- Deletion threshold lowered to 50 – a mass mistake stops before export.

## 9. Skills practised

- Sync scope semantics (out of scope = deleted), soft delete and restore
- Leaver process ordering
