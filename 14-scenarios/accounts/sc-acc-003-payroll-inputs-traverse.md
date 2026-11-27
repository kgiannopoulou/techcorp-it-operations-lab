# SC-ACC-003: Payroll officer cannot "find" the payroll inputs

| Field | Value |
|---|---|
| Scenario ID | SC-ACC-003 |
| Category | Accounts |
| Difficulty | ⭐⭐ |
| Priority (if real) | P2 – payroll deadline |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | VirtualBox: TC-DC01, TC-FS01, TC-LT-LAB01 signed in as `hitch.dreyse` |

## 1. The report

> *"HR says the monthly inputs are in their Payroll-Inputs folder. When I open the Departments folder I don't even see HR, and if I type the HR path I get access denied."* – Hitch Dreyse, Payroll & Accounts Officer

## 2. Environment / context

`hitch.dreyse` is in `GG_Finance_Payroll` → `DL_FS_HR-PayrollInputs_RO`
(read on `Departments\HR\Payroll-Inputs`). He has no access to
`Departments\HR` itself. This is **by design** (HR data is HR-only, BR-26).
His P: drive mapping was not yet configured.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

The P: item in `U-AllUsers-DriveMappings` is disabled (or not yet created).

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Browse | `Get-ChildItem \\corp.techcorp.example\dfs\Departments` | Finance only – HR hidden by ABE | ABE working as designed |
| 2 | Parent folder | `Get-ChildItem …\Departments\HR` | Access denied | Correct – no access to HR |
| 3 | Direct path | `Get-ChildItem …\Departments\HR\Payroll-Inputs` | **Works** | *Bypass traverse checking* lets him pass through HR without access to it |
| 4 | Plan model | `Get-TechCorpAdPlan.ps1 -Summary` row hitch.dreyse | HR `-`, HR\Payroll-Inputs `R` | Matches the design |
| 5 | His drives | `Get-PSDrive -PSProvider FileSystem` | No P: | The missing piece |

## 5. Root cause

Not a permissions fault: the user was trying to *browse* to a folder he may
only *open directly*. The drive mapping that gives him that direct path was missing.

## 6. Resolution

Enable/create the P: item (path `\\corp.techcorp.example\dfs\Departments\HR\Payroll-Inputs`,
targeting `GG_Finance_Payroll`); user logs off/on. Do **not** give Finance
List rights on the HR folder – that would reveal HR's folder names and break
least privilege.

## 7. Verification

`P:` opens with the inputs; `Departments\HR` still denied; HR's
`access-tests.csv` rows still pass in CI.

## 8. Prevention

Every cross-department grant gets its drive mapping in the same change.

## 9. Skills practised

- Traverse vs list vs read; ABE; least privilege
- Explaining "working as designed" to a user under deadline pressure

## 10. Related

- [ntfs-and-share-permissions.md](../../03-windows-server/permissions/ntfs-and-share-permissions.md)
- [gpo-design.md §4](../../03-windows-server/group-policy/gpo-design.md#4-drive-mappings-u-allusers-drivemappings)
