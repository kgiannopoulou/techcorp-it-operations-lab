# SC-ACC-002: Added to Finance – still "Access denied"

| Field | Value |
|---|---|
| Scenario ID | SC-ACC-002 |
| Category | Accounts |
| Difficulty | ⭐ |
| Priority (if real) | P3 – single user |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | VirtualBox: TC-DC01, TC-FS01, TC-LT-LAB01 signed in as `sasha.blouse` |

## 1. The report

> *"Dot said you gave me access to the Finance folder for the audit this morning, but it still says I don't have permission."* – Sasha Blouse, HR & Office Coordinator

## 2. Environment / context

At 10:05 `sasha.blouse` was temporarily added to `GG_Finance_Users`
(approved by the Finance Manager). She has been signed in since 08:30.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

No fault – sign in as sasha.blouse, then `Add-ADGroupMember GG_Finance_Users -Members sasha.blouse` on the DC and try the folder without logging off.

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Is she in the group in AD? | `Get-ADGroupMember GG_Finance_Users` | Yes | AD is correct |
| 2 | Is the group in her **token**? | `whoami /groups` on her session | `GG_Finance_Users` / `DL_FS_Finance_RW` **missing** | Token pre-dates the change |
| 3 | Kerberos tickets | `klist` | TGT issued 08:30 | Group SIDs are fixed in the ticket at logon |

## 5. Root cause

Group membership is evaluated when the Kerberos TGT is issued (logon). The
file server builds her access token from the service ticket, which still
carries the old group list.

## 6. Resolution

Log off and on (or lock/unlock is **not** enough). Without logging off:
`klist purge`, then reconnect to the share – a new ticket with the new
groups is requested.

## 7. Verification

`whoami /groups` shows `GG_Finance_Users`; `T:`-path / Finance folder opens.
Afterwards remove her again (`Deploy-TechCorpAd.ps1 -RemoveUnexpectedMembers` reports and removes it).

## 8. Prevention

Ticket template for access requests includes "please sign out and in after
we confirm". Temporary access gets an end date in the ticket.

## 9. Skills practised

- Access tokens and Kerberos tickets (`whoami /groups`, `klist`)
- AGDLP in practice

## 10. Related

- [groups-agdlp.md §4](../../03-windows-server/users-and-groups/groups-agdlp.md#4-operational-notes)
