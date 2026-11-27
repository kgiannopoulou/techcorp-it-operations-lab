# SC-M365-005: support@ does not show up in Outlook

| Field | Value |
|---|---|
| Scenario ID | SC-M365-005 |
| Category | Microsoft 365 |
| Difficulty | ⭐ |
| Priority (if real) | P3 – single user, OWA workaround |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | Lab tenant |

## 1. The report

> *"Petra says I have access to the support mailbox now, but Outlook only shows my own."* – Oluo Bozado, Customer Support Specialist

## 2. Environment / context

To "save time" access was granted to a new mail-enabled security group *Support Team* instead of per user from `mailboxes.csv`.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

`Remove-MailboxPermission support -User oluo.bozado -AccessRights FullAccess`, then grant Full Access to a mail-enabled security group containing him.

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Can he open it at all? | OWA → *Open another mailbox* → support@ | Opens | Permission works |
| 2 | Permission entries | `Get-EXOMailboxPermission support` | Full Access for the group, not for Oluo | Granted via group |
| 3 | Auto-mapping | – | Auto-mapping only works for **direct** user grants | Outlook won't add it automatically |
| 4 | Plan comparison | `Test-TechCorpM365.ps1` | support@ Full Access FAIL – missing oluo.bozado, unexpected group | Drift from mailboxes.csv |

## 5. Root cause

Full Access through a group gives access but disables auto-mapping, so the
mailbox doesn't appear in Outlook's folder pane.

## 6. Resolution

Run `Deploy-TechCorpM365.ps1 -Skip Users,Licensing,Teams,SharePoint` (grants per user with auto-mapping from `mailboxes.csv`), remove the group grant. Outlook shows the mailbox after restart (up to 60 min).

## 7. Verification

support@ in Oluo's Outlook folder list; `Test-TechCorpM365.ps1` Mail rows PASS.

## 8. Prevention

Shared-mailbox access only through `mailboxes.csv`; the plan test catches group grants.

## 9. Skills practised

- Exchange permissions vs auto-mapping
- Detecting drift with a read-only test
