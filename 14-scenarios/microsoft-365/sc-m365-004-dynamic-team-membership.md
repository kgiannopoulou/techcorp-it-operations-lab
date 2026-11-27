# SC-M365-004: New marketing hire is not in the Sales & Marketing team

| Field | Value |
|---|---|
| Scenario ID | SC-M365-004 |
| Category | Microsoft 365 |
| Difficulty | ⭐⭐ |
| Priority (if real) | P3 – single user |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | Lab AD + Entra Connect + lab tenant |

## 1. The report

> *"Pieck can't see the Sales & Marketing team or its files. Everyone else in the department can."* – Jean Kirstein

## 2. Environment / context

Pieck Finger's account was edited by hand in ADUC last week (job title change) and the department field was retyped.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

`Set-ADUser pieck.finger -Department 'Sales and Marketing'` (instead of `Sales & Marketing`), delta sync.

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Team membership | Entra admin center → grp-sales → Members | Pieck missing | Rule doesn't match her |
| 2 | Rule | Group → *Dynamic membership rules* | `user.department -eq "Sales & Marketing"` | Exact string match |
| 3 | Validate rule against the user | *Validate Rules* tab → add pieck.finger | ❌ `user.department` = `Sales and Marketing` | Attribute differs |
| 4 | Source | `Get-ADUser pieck.finger -Properties Department` | `Sales and Marketing` | Edited in AD by hand |
| 5 | Plan comparison | `Test-TechCorpAd.ps1` | User row FAIL – department | Drift detected by the plan |

## 5. Root cause

The department attribute in AD no longer matches `employees.csv`; dynamic
membership depends on the exact value.

## 6. Resolution

Run `Deploy-TechCorpAd.ps1` – it resets the attribute from `employees.csv` –
then a delta sync. Membership updates after dynamic-group processing.

## 7. Verification

Pieck in grp-sales members; Teams shows the team (sign out/in of Teams if needed); `Test-TechCorpAd.ps1` user row PASS.

## 8. Prevention

- HR data is changed in `employees.csv`, never directly in ADUC.
- Weekly `Test-TechCorpAd.ps1` (maintenance calendar, Phase 11).

## 9. Skills practised

- Dynamic group rules and the *Validate Rules* tool
- Treating the repository as the source of truth
