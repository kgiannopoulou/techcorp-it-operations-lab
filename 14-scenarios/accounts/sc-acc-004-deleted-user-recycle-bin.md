# SC-ACC-004: The wrong Ackerman was deleted

| Field | Value |
|---|---|
| Scenario ID | SC-ACC-004 |
| Category | Accounts |
| Difficulty | ⭐⭐ |
| Priority (if real) | P2 – key person cannot work |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | VirtualBox: TC-DC01, TC-DC02 |

## 1. The report

> *"I can't sign in – it says the user name or password is incorrect. Nothing changed."* – Mikasa Ackerman, Software Developer

## 2. Environment / context

During a clean-up of test accounts someone deleted `CN=Mikasa Ackerman` instead
of a test account called `Ackerman Test`. AD Recycle Bin was enabled at
domain build ([ad-ds-deployment.md](../../03-windows-server/active-directory/ad-ds-deployment.md) A6).

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

`Remove-ADUser mikasa.ackerman -Confirm:$false`

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Does the account exist? | `Get-ADUser mikasa.ackerman` | Cannot find an object | Not a password problem |
| 2 | Was it deleted? | `Get-ADObject -Filter 'samAccountName -eq "mikasa.ackerman"' -IncludeDeletedObjects -Properties whenChanged, lastKnownParent` | Object in *Deleted Objects*, `lastKnownParent` = `OU=Development,…` | Restorable |
| 3 | Who deleted it? | Security log on DCs, event **4726** (audit GPO) | Subject = admin account, time | Process issue to discuss |

## 5. Root cause

Accidental deletion. (Protected-from-deletion is set on OUs, not on user accounts.)

## 6. Resolution

```powershell
Get-ADObject -Filter 'samAccountName -eq "mikasa.ackerman"' -IncludeDeletedObjects | Restore-ADObject
```

The Recycle Bin restores **all** attributes, including group memberships
(`memberOf` back-links) and the password – she signs in with her usual password.

## 7. Verification

`Test-TechCorpAd.ps1`: user and all group rows PASS; she opens `T:` (Development).

## 8. Prevention

- Delete only from the `Disabled` OU, after 30 days (leaver procedure).
- Search by `sAMAccountName`, not by display name, when scripting deletions.

## 9. Skills practised

- AD Recycle Bin, `Restore-ADObject`, deleted-object lifetime (180 days)
- Audit events 4726

## 10. Related

- [user-accounts.md §4](../../03-windows-server/users-and-groups/user-accounts.md#4-account-lifecycle-automated-in-m8)
