# SC-PS-002: The new developer's e-mail address is "connie.springer2"

| Field | Value |
|---|---|
| Scenario ID | SC-PS-002 |
| Category | Automation / Accounts |
| Difficulty | ⭐ |
| Priority (if real) | P4 – cosmetic, but HR asks for a fix before day 1 |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | VirtualBox: TC-DC01; `New-TechCorpUser.ps1` |

## 1. The report

> *"Our new starter is called Connie Springer – the welcome sheet says connie.springer2. She is not a number two. Can you fix it?"* – Sasha Blouse, HR & Office Coordinator

## 2. Environment / context

Three weeks ago Connie Springer (Sales) left and was offboarded with
`Disable-TechCorpUser.ps1`. Today a *different* person with the same name
joins Software Development. `employees.csv` no longer contains the old
Connie, but `New-TechCorpUser.ps1` produced `connie.springer2`.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

Not a fault – correct behaviour that looks like one. Offboard
`connie.springer`, remove her from `employees.csv`, then onboard a new
"Connie Springer".

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Is the name taken? | `Get-ADUser -Filter "SamAccountName -like 'connie.springer*'" -Properties Enabled, Description, WhenChanged` | `connie.springer`, disabled, in `TechCorp/Disabled`, description *Left 2027-… HD-…* | The leaver's account is in its 30-day retention |
| 2 | What happens to her mailbox? | `Get-EXOMailbox connie.springer@techcorp.example` | Shared mailbox, manager has Full Access, out-of-office points to her manager | The address is **still in use** |
| 3 | What would re-using the name do? | Think it through | Customers still e-mail the old address; the new Connie would receive the leaver's mail and the leaver's OneDrive links | Re-use is a data-protection incident (BR-26) |

## 5. Root cause

The script checks `employees.csv` **and** Active Directory for the base name
(`Get-TcUsername` with the AD accounts as `-Existing`), so a name is never
re-used while the leaver's account, mailbox and address exist.

## 6. Resolution

Explain to HR why the number stays, and offer the usual alternative instead
of `2`: run the script with the name the person is known by (for example the
middle name, `-FirstName 'Connie Marie'` → `conniemarie.springer`). Do not
rename the leaver's account to free the name.

Six months after the shared mailbox is removed the name may be re-used –
note it in the leaver record.

## 7. Verification

The welcome sheet and `onboarding-<date>.csv` show the agreed name; the
leaver's shared mailbox is untouched.

## 8. Prevention

- Add the rule to the joiner procedure: *logon names are never re-used while the old mailbox exists* ([user-accounts.md §4](../../03-windows-server/users-and-groups/user-accounts.md#4-account-lifecycle-automated-in-m8)).
- HR sees the planned name in the `-PlanOnly` output **before** the welcome pack is printed.

## 9. Skills practised

- Why identity names are not re-used; data protection in lifecycle processes
- Reading the script's plan output instead of trusting it

## 10. Related

- [New-TechCorpUser.ps1](../../07-powershell/user-management/New-TechCorpUser.ps1) · SC-ACC-004 (deleting the wrong account)
