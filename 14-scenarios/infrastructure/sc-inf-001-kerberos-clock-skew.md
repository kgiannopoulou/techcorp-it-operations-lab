# SC-INF-001: "The time difference between the client and server is too large"

| Field | Value |
|---|---|
| Scenario ID | SC-INF-001 |
| Category | Infrastructure |
| Difficulty | ⭐⭐ |
| Priority (if real) | P2 – every user on the affected DC |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | VirtualBox: TC-DC01, TC-DC02, TC-LT-LAB01 |

## 1. The report

> *"Some people can't open the shared drives after lunch, others can. Teams works for everyone."* – Hange Zoe, Operations Manager

## 2. Environment / context

TC-DC02's VM was paused for an hour on the lab host and resumed. Clients that
authenticate against DC02 fail; clients on DC01 are fine.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

On TC-DC02: `Stop-Service w32time; Set-Date (Get-Date).AddMinutes(-9)` (VirtualBox host time sync is disabled on DCs, so nothing corrects it).

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Which DC does a failing client use? | `nltest /dsgetdc:corp.techcorp.example` | TC-DC02 | Pattern = one DC |
| 2 | Kerberos errors | DC Security log 4771 failure code `0x25` / client System log Kerberos event | Clock skew | Not permissions |
| 3 | Compare clocks | `w32tm /stripchart /computer:TC-DC02 /samples:3 /dataonly` from DC01 | ≈ –540 s | 9 minutes behind (limit 5) |
| 4 | Time service on DC02 | `w32tm /query /status` / `Get-Service w32time` | Stopped / source *Local CMOS Clock* | Hierarchy broken |
| 5 | Replication side-effect | `repadmin /replsummary` | Errors from DC02 | Skew also breaks replication |

## 5. Root cause

Kerberos tickets are only accepted within 5 minutes of the DC's clock. DC02's
time drifted with no running time service to bring it back to the PDC.

## 6. Resolution

```powershell
# on TC-DC02
Start-Service w32time
w32tm /config /syncfromflags:domhier /update
w32tm /resync /rediscover
```

Clients: `klist purge` or log off/on.

## 7. Verification

`w32tm /monitor` shows both DCs within 1 s; failing users can open shares;
`repadmin /replsummary` clean.

## 8. Prevention

- `GetHostTimeDisabled` on DC VMs (server-build step 1) – the domain hierarchy, not the hypervisor, owns time.
- Monitoring of `w32tm /monitor` offsets (Phase 11).

## 9. Skills practised

- Windows time hierarchy, PDC emulator role
- Kerberos failure codes

## 10. Related

- [ad-ds-deployment.md](../../03-windows-server/active-directory/ad-ds-deployment.md)
- [ad-troubleshooting.md](../../03-windows-server/active-directory/ad-troubleshooting.md)
