# SC-WIN-003: Nobody gets the new Managers drive

| Field | Value |
|---|---|
| Scenario ID | SC-WIN-003 |
| Category | Windows |
| Difficulty | ⭐⭐ |
| Priority (if real) | P3 – new feature not working, workaround (UNC path) exists |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | VirtualBox: TC-DC01, TC-FS01, TC-LT-LAB01 signed in as `petra.ral` |

## 1. The report

> *"You said all managers get an M: drive from today. I logged off and on twice – no M:."* – Petra Ral, Customer Support Lead

## 2. Environment / context

The M: item was added to a **new** GPO `U-Managers-DriveMapping` created in a
hurry. The GPO was linked to `TechCorp/Computers` because "that's where the
laptops are". Other drives (S:, T:) still work – they come from `U-AllUsers-DriveMappings`.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

```powershell
New-GPO -Name U-Managers-DriveMapping | New-GPLink -Target 'OU=Computers,OU=TechCorp,DC=corp,DC=techcorp,DC=example'
```

…with an M: drive map in *User Configuration → Preferences*.

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Does the user have access to the share? | `Get-ChildItem \\corp.techcorp.example\dfs\Managers` | Works | Permissions are fine – it's the mapping |
| 2 | User policy result | `gpresult /r /scope user` | `U-Managers-DriveMapping` not listed at all | GPO not in the user's scope |
| 3 | Where is the user? Where is the GPO? | `([adsisearcher]"samaccountname=petra.ral").FindOne().Path` · `Get-GPInheritance -Target 'OU=Users,OU=TechCorp,…'` | User in `TechCorp/Users/Support`; GPO linked only on `TechCorp/Computers` | User settings apply to **user objects** in the linked OU |
| 4 | CI would have caught it | `Get-TechCorpAdPlan.ps1 -SelfTest` after adding it to `gpo-plan.csv` | `user GPO … must be linked where the users are` | Process was bypassed |

## 5. Root cause

A GPO's *User Configuration* applies to user accounts in (or below) the OU it
is linked to. Linked to a computer OU, it never applies to anyone.
(Loopback processing would make it work, but would be the wrong tool here.)

## 6. Resolution

Add the M: item to the existing `U-AllUsers-DriveMappings` (targeting
`GG_All_Managers`) as designed, and delete the stray GPO; or, minimum fix,
link it to `TechCorp/Users`.

## 7. Verification

Log off/on as `petra.ral`: `Get-PSDrive M` exists; `annie.leonhart` (not a
manager) gets no M:.

## 8. Prevention

- New GPOs go into `gpo-plan.csv` first – CI enforces link targets.
- One drive-mapping GPO with item-level targeting instead of one GPO per group.

## 9. Skills practised

- User vs computer configuration scope, GPO links, `gpresult`
- Group Policy Preferences item-level targeting

## 10. Related

- [gpo-design.md §4 Drive mappings](../../03-windows-server/group-policy/gpo-design.md#4-drive-mappings-u-allusers-drivemappings)
- [ou-design.md](../../03-windows-server/users-and-groups/ou-design.md)
