# SC-WIN-004: Developers get Microsoft 365 sign-in prompts all day

| Field | Value |
|---|---|
| Scenario ID | SC-WIN-004 |
| Category | Windows |
| Difficulty | ⭐⭐⭐ |
| Priority (if real) | P3 – one department, annoying but working |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | VirtualBox: TC-DC01 (+ Entra Connect), TC-LT-LAB01 in the Developer OU, lab tenant |

## 1. The report

> *"Teams and Outlook keep asking me to sign in, and OneDrive never set itself up. Mikasa has the same. Sales people say they never see this."* – Armin Arlert, Senior Software Developer

## 2. Environment / context

All Developer-tier laptops, built last week. Standard-tier laptops are fine.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

In Entra Connect *Domain and OU filtering*, `TechCorp/Computers/Workstations/Developer` was unticked ("only users need syncing").

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Device state | `dsregcmd /status` | `DomainJoined : YES`, `AzureAdJoined : NO`, no PRT | Not hybrid joined → no SSO to M365 |
| 2 | Same on a Sales laptop | `dsregcmd /status` | `AzureAdJoined : YES` | Pattern = OU / tier |
| 3 | SCP and registration task | `dsregcmd /status` → *Diagnostic Data*; Task Scheduler → *Workplace Join* | Registration attempted, "device not found" | The cloud has no device object to match |
| 4 | Entra Connect scope | Sync Service Manager → connector → *Configure Directory Partitions → Containers* | Developer OU unticked | Root cause |
| 5 | Compare with the design | `ou-structure.csv` `EntraSync` column | Developer = Yes | Server config drifted from the repo |

## 5. Root cause

Hybrid join needs the computer object synced to Entra ID first; the Developer
OU was removed from the sync scope, so those laptops can never complete
registration and never get a Primary Refresh Token.

## 6. Resolution

Re-tick the OU in the Entra Connect wizard, run a delta sync, then on each
laptop sign out/in (or reboot). `dsregcmd /status` shows `AzureAdJoined : YES`
and `AzureAdPrt : YES` in the user session.

## 7. Verification

`Test-TechCorpEndpoint.ps1` Identity rows PASS on a developer laptop; Teams
opens without a prompt; OneDrive configures itself (silent account config).

## 8. Prevention

- Sync scope lives in `ou-structure.csv`; CI rejects a scope without the workstation OUs.
- After any Entra Connect wizard change: export the configuration (*View or export current configuration*) and compare with the repo.

## 9. Skills practised

- Hybrid join mechanics (SCP, device sync, PRT), `dsregcmd`
- Configuration drift between a server and its documented design

## 10. Related

- [entra-connect-sync.md](../../05-microsoft-365/entra-connect/entra-connect-sync.md)
- [endpoint-troubleshooting.md](../../04-endpoint-management/troubleshooting/endpoint-troubleshooting.md)
