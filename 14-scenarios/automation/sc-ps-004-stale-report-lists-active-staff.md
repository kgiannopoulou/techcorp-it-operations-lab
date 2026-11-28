# SC-PS-004: The stale-account report says half the office hasn't logged on for seven weeks

| Field | Value |
|---|---|
| Scenario ID | SC-PS-004 |
| Category | Automation / Infrastructure |
| Difficulty | ⭐⭐⭐ |
| Priority (if real) | P2 – the report hides a directory replication failure |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | VirtualBox: TC-DC01, TC-DC02 |

## 1. The report

> *"The monthly review lists Levi, Armin, Petra … as 'Inactive, 49 days'. They're at their desks right now. Is the script wrong?"* – Hange Zoe, Operations Manager

## 2. Environment / context

`Get-TechCorpStaleAccountReport.ps1` was run from the admin PC with
`-Server TC-DC02` (TC-DC01 was being patched). The users sign in every day.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

On TC-DC02: `repadmin /options TC-DC02 +DISABLE_INBOUND_REPL`, then
advance the lab clock / wait, and let users log on against TC-DC01 only.

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Same report against the other DC | `Get-TechCorpStaleAccountReport.ps1 -Server TC-DC01` | Those users are **not** listed | The data differs between DCs |
| 2 | Is `LastLogonDate` replicated? | Docs: it is `lastLogonTimestamp`, replicated (updates every 9–14 days) | Should be the same on both DCs within ~14 days | 49 days means TC-DC02 is not receiving changes |
| 3 | Replication status | `repadmin /showrepl TC-DC02`, `repadmin /replsummary` | Inbound replication disabled / last success 49 days ago | Replication failure |
| 4 | Is it older than the tombstone lifetime? | `(Get-ADObject 'CN=Directory Service,CN=Windows NT,CN=Services,CN=Configuration,DC=corp,DC=techcorp,DC=example' -Properties tombstoneLifetime).tombstoneLifetime` | 180 days | Still recoverable – no lingering objects yet |

## 5. Root cause

TC-DC02 stopped inbound replication 49 days ago. Its copy of
`lastLogonTimestamp` (and every other change: new users, password changes,
group memberships) is 49 days old. The script reported correctly what that
DC knows – the report was the first thing to notice the broken DC.

## 6. Resolution

```powershell
repadmin /options TC-DC02 -DISABLE_INBOUND_REPL
repadmin /syncall TC-DC02 /AdeP
repadmin /replsummary
```

Re-run the report against either DC – the list shrinks to genuinely stale accounts.

## 7. Verification

`repadmin /replsummary` shows 0 failures; both DCs give the same stale list.

## 8. Prevention

- Add a replication check to the daily check (`repadmin /replsummary` → FAIL on errors) – recorded for M12 monitoring.
- Run the monthly review against the PDC emulator (`-Server TC-DC01`) by default.

## 9. Skills practised

- `lastLogon` vs `lastLogonTimestamp`; AD replication and its tools
- Treating an "obviously wrong" report as a symptom, not a bug

## 10. Related

- [Get-TechCorpStaleAccountReport.ps1](../../07-powershell/reporting/Get-TechCorpStaleAccountReport.ps1) · SC-INF-001 (time on DCs)
