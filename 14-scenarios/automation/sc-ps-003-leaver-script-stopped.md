# SC-PS-003: The leaver script stopped half way – is she offboarded or not?

| Field | Value |
|---|---|
| Scenario ID | SC-PS-003 |
| Category | Automation / Microsoft 365 |
| Difficulty | ⭐⭐ |
| Priority (if real) | P2 – a leaver may still have access (BR-10: same day) |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | VirtualBox: TC-DC01, TC-SYNC01; lab tenant |

## 1. The report

> *"I ran the leaver script for Annie at 17:40 – it printed red text and `Stop / Refused`. HR wants confirmation that she can't get in any more."* – Eren Yeager, IT Specialist (own note)

## 2. Environment / context

`Disable-TechCorpUser.ps1 -Identity annie.leonhart -Ticket HD-2027-0117 -IncludeCloud`
was run on the admin PC. `Connect-ExchangeOnline` had been run at 09:00 for
something else; `Connect-MgGraph` just before the script.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

Connect to Exchange Online, then leave the session idle until the token
expires (or `Disconnect-ExchangeOnline` in another window of the same
session) and run the leaver script.

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Which steps ran? | The step table on screen, or `output\logs\Disable-TechCorpUser.log` | `Record Done`, `Revoke sessions Done`, `Mailbox to shared Failed`, `Stop Refused` | Sessions revoked; nothing in AD changed |
| 2 | Why did the mailbox step fail? | Detail column | *"The term 'Set-Mailbox' is not recognized"* / session expired | EXO not connected any more |
| 3 | Can she still sign in? | Entra admin center → user → *Sign-in logs*; AD `Get-ADUser annie.leonhart -Properties Enabled` | Tokens revoked, but the account is still **enabled** – a new sign-in with her password works | Not offboarded yet |
| 4 | Why did the script stop instead of carrying on? | Script design | Removing the groups removes `LIC_M365_BusinessPremium`; without the shared conversion first, the mailbox would be deleted with the licence after 30 days | The stop is deliberate |

## 5. Root cause

An expired Exchange Online session. The script's safety stop worked: it
refused to remove the licence group while the mailbox was still a user
mailbox, so no data was lost – but the account stayed enabled.

## 6. Resolution

```powershell
Connect-ExchangeOnline
.\Disable-TechCorpUser.ps1 -Identity annie.leonhart -Ticket HD-2027-0117 -IncludeCloud
```

Every step is safe to repeat (revoking again, converting an already shared
mailbox, removing groups that are already gone). The leaver record now has
two rows for the ticket; the first one holds the original groups.

If Exchange Online cannot be reached at all: `Disable-ADAccount annie.leonhart`
now (same-day requirement) and run the full script when it is back.

## 7. Verification

Step table all `Done`/`MANUAL`; `Get-ADUser annie.leonhart -Properties Enabled` → `False`,
in `TechCorp/Disabled`; `Get-EXOMailbox annie.leonhart -Properties RecipientTypeDetails` → `SharedMailbox`;
after the next sync the Entra user shows *Sign-in blocked*.

## 8. Prevention

- Connect to Graph and EXO immediately before the script (it says so in its help).
- Consider a pre-flight check in the script: `Get-ConnectionInformation` before step 1 – recorded as an improvement.

## 9. Skills practised

- Reading a step log; idempotent re-runs
- Why order matters in offboarding (licence vs mailbox)

## 10. Related

- [Disable-TechCorpUser.ps1](../../07-powershell/user-management/Disable-TechCorpUser.ps1) · [licensing-and-lifecycle.md §4](../../05-microsoft-365/user-management/licensing-and-lifecycle.md#4-leaver-same-day--br-10) · SC-M365-003
