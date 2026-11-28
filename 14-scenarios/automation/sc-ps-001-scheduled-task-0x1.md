# SC-PS-001: The daily-check e-mail stopped arriving after the scripts were updated

| Field | Value |
|---|---|
| Scenario ID | SC-PS-001 |
| Category | Automation |
| Difficulty | ⭐⭐ |
| Priority (if real) | P3 – monitoring blind spot, no user impact yet |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | VirtualBox: TC-FS01 (scheduled task), TC-DC01 |

## 1. The report

> *"I haven't had the 08:30 report since Tuesday. Is everything OK, or is the report broken?"* – Hange Zoe, Operations Manager

## 2. Environment / context

The *TechCorp daily check* task on TC-FS01 runs
`Invoke-TechCorpDailyCheck.ps1` as a gMSA. On Monday the scripts folder was
refreshed by downloading the repository as a ZIP from GitHub in a browser and
extracting it over `D:\Shares\IT\Scripts`, instead of `git pull`.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

Download the repository ZIP with Edge on TC-FS01, extract it over the scripts
folder. Every file now has a `Zone.Identifier` alternate data stream (Mark of
the Web, zone 3 = Internet). The task runs with `-ExecutionPolicy RemoteSigned`.

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Did the task run? | `Get-ScheduledTaskInfo 'TechCorp daily check'` | `LastRunTime` today 08:00, `LastTaskResult` **1** | It runs, but the script fails |
| 2 | What does the script say when run the same way? | `powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File …\Invoke-TechCorpDailyCheck.ps1` | *"… is not digitally signed. You cannot run this script on the current system"* | Execution policy, not the code |
| 3 | Why is a local file "remote"? | `Get-Item …\Invoke-TechCorpDailyCheck.ps1 -Stream Zone.Identifier` | `ZoneId=3` | Mark of the Web from the browser download |
| 4 | Is it only this file? | `Get-ChildItem D:\Shares\IT\Scripts -Recurse -File \| Get-Item -Stream Zone.Identifier -ErrorAction SilentlyContinue` | Every file | The whole copy is marked |
| 5 | Why did nobody notice for three days? | The task's exit code | 1 = WARN, the same as a normal "disk 18 % free" day | Nothing alerts on the task itself |

## 5. Root cause

Files downloaded through a browser keep the Mark of the Web. `RemoteSigned`
only runs such scripts when they are signed; ours are not. The update
procedure was skipped (ZIP instead of `git pull`), and a failure of the job
itself looked like an ordinary WARN.

## 6. Resolution

```powershell
# compare with the repository first - never unblock what you have not checked
git -C D:\Shares\IT\Scripts status
Get-ChildItem D:\Shares\IT\Scripts -Recurse -File | Unblock-File
Start-ScheduledTask 'TechCorp daily check'
```

Better: delete the folder and `git clone` it again, so the files never carry the mark.

## 7. Verification

`Get-ScheduledTaskInfo` → `LastTaskResult` 0 or 1 with today's
`daily-check-<date>.html` present; the e-mail arrives.

## 8. Prevention

- Scripts on servers are updated only with `git pull` (documented in [07-powershell](../../07-powershell/README.md#scheduling)).
- Alert when the report file is **missing** (the exit code cannot tell "WARN" from "did not start") – monitoring, M12.
- Later: sign the scripts with an internal code-signing certificate and use `AllSigned`.

## 9. Skills practised

- Execution policies, Mark of the Web, `Unblock-File`, alternate data streams
- Scheduled task results and why an exit code alone is not monitoring

## 10. Related

- [Invoke-TechCorpDailyCheck.ps1](../../07-powershell/maintenance/Invoke-TechCorpDailyCheck.ps1)
