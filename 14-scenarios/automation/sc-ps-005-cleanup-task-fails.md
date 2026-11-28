# SC-PS-005: The weekly clean-up job "fails" every Sunday – and the reports folder is full

| Field | Value |
|---|---|
| Scenario ID | SC-PS-005 |
| Category | Automation |
| Difficulty | ⭐⭐ |
| Priority (if real) | P3 – disk filling slowly on TC-FS01 |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | VirtualBox: TC-FS01 |

## 1. The report

> *"Daily check: TC-FS01 D: 17 % free, WARN. The clean-up task shows last result 1 every Sunday."* – daily-check e-mail

## 2. Environment / context

The *TechCorp report clean-up* task was changed so the folder comes from an
environment variable (one task definition for every server). Its action is now
`powershell.exe -NoProfile -Command "& D:\Shares\IT\Scripts\07-powershell\maintenance\Remove-TechCorpOldFile.ps1 -Path $env:TC_REPORTS -OlderThanDays 90 -Recurse -Force -Confirm:$false"`.
`TC_REPORTS` was set with `setx` while logged on as `adm-eren.yeager`.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

Set `TC_REPORTS` as a **user** environment variable of the admin account only,
and register the task to run as the gMSA with the action above.

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | What did the script log? | `output\logs\Remove-TechCorpOldFile.log` | Nothing since the change | The script never started |
| 2 | Run the action by hand as the task would | Same command line in a console of the admin account | Works – files are listed | It depends on who runs it |
| 3 | Look at the variable from the task's point of view | Temporary task action `cmd /c set > C:\Temp\env.txt` as the gMSA | No `TC_REPORTS` | The gMSA does not have it |
| 4 | Where is the variable? | `[Environment]::GetEnvironmentVariable('TC_REPORTS', 'User')` vs `'Machine'` | Set for the admin user only | `setx` without `/M` writes the user's environment |
| 5 | What does the script do with an empty path? | `.\Remove-TechCorpOldFile.ps1 -Path $null -OlderThanDays 90` | *Cannot bind argument to parameter 'Path' because it is null* – exit 1 | Mandatory parameter, no default: it refuses to guess |

## 5. Root cause

The task's path came from a variable that only existed for another account,
so the script received an empty `-Path` and PowerShell refused to bind it. The
clean-up never ran and the folder kept growing. Nothing was deleted.

Had `-Path` defaulted to "the current folder", the task would have run in its
working directory, `C:\Windows\System32` – there the second safety rail (no
system folders) would have refused.

## 6. Resolution

Put the literal path in the task's arguments (or set the variable machine-wide
with `setx TC_REPORTS D:\Shares\IT\Reports /M` and restart the task scheduler
service so it sees it), then:

```powershell
.\Remove-TechCorpOldFile.ps1 -Path D:\Shares\IT\Reports -OlderThanDays 90 -Recurse -WhatIf   # check the list first
Start-ScheduledTask 'TechCorp report clean-up'
```

## 7. Verification

Log line `D:\Shares\IT\Reports: N of N file(s) older than 90 days deleted`;
next daily check shows D: above 20 % free.

## 8. Prevention

- Scheduled tasks get full, literal paths – nothing that depends on who is logged on.
- Destructive scripts take a mandatory path with no default, and refuse system and profile folders (both already true – keep them).
- The daily check should notice a task whose log has not changed for a week – recorded for M12 monitoring.

## 9. Skills practised

- Scheduled task environment: working directory, user vs machine variables
- Defensive scripting: refuse, don't guess

## 10. Related

- [Remove-TechCorpOldFile.ps1](../../07-powershell/maintenance/Remove-TechCorpOldFile.ps1) · SC-PS-001 (another task failure)
