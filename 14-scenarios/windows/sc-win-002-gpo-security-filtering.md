# SC-WIN-002: Finance can write to USB sticks again

| Field | Value |
|---|---|
| Scenario ID | SC-WIN-002 |
| Category | Windows |
| Difficulty | ⭐⭐⭐ |
| Priority (if real) | P2 – GDPR control silently not enforced |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | VirtualBox: TC-DC01, TC-LT-LAB01 signed in as `nile.dok` |

## 1. The report

> *"I could copy the payroll export to my USB stick today – I thought that was blocked?"* – Nile Dok, Accountant

## 2. Environment / context

Last week someone "tidied up" the GPO `U-FinanceHR-RemovableStorage` in
GPMC: under *Security Filtering* they removed *Authenticated Users* and kept
only `GG_Finance_Users` and `GG_HR_Users`. GPMC still shows the GPO linked
and enabled.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

`Set-GPPermission -Name U-FinanceHR-RemovableStorage -TargetName 'Authenticated Users' -TargetType Group -PermissionLevel None -Replace`

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Is the setting applied? | `gpresult /r /scope user` as nile.dok | GPO listed under *not applied* – *Filtering: Denied (Security)* / inaccessible, or missing entirely | Not a client-side setting problem |
| 2 | Is the user in the filter group? | `whoami /groups` | `TECHCORP\GG_Finance_Users` present | Group filter is right |
| 3 | GPO delegation | GPMC → GPO → *Delegation* tab | No entry for Authenticated Users / Domain Computers | Computer account cannot **read** the GPO |
| 4 | Why does the computer matter for a *user* GPO? | – | Since MS16-072 user policy is retrieved using the computer's security context | Missing Read = GPO invisible |
| 5 | Automated check | `Test-TechCorpAd.ps1` | `U-FinanceHR-RemovableStorage: Authenticated Users = Read (MS16-072)` → FAIL | Confirms |

## 5. Root cause

Security filtering was edited by removing Authenticated Users instead of
reducing it to *Read*. The computer can no longer read the GPO, so the user
part is never processed.

## 6. Resolution

```powershell
Set-GPPermission -Name U-FinanceHR-RemovableStorage -TargetName 'Authenticated Users' `
    -TargetType Group -PermissionLevel GpoRead
```

Or simply re-run `Deploy-TechCorpGpo.ps1`, which enforces the plan.
Then on the client: `gpupdate /force`, log off/on.

## 7. Verification

`gpresult /r /scope user` lists the GPO as applied; copying a file to USB
fails with *You need permission*; `Test-TechCorpAd.ps1` GPO rows PASS.

## 8. Prevention

- GPO changes only through `gpo-plan.csv` + the deploy script, which always keeps AU Read.
- Weekly `Test-TechCorpAd.ps1` run (Phase 11 maintenance calendar).

## 9. Skills practised

- `gpresult` interpretation, GPO security filtering vs delegation
- MS16-072 behaviour

## 10. Related

- [gpo-design.md](../../03-windows-server/group-policy/gpo-design.md)
- [gpo-procedures.md](../../03-windows-server/group-policy/gpo-procedures.md)
