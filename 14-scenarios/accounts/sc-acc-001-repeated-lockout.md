# SC-ACC-001: Account locked out every morning

| Field | Value |
|---|---|
| Scenario ID | SC-ACC-001 |
| Category | Accounts |
| Difficulty | ⭐⭐ |
| Priority (if real) | P3 – single user, repeated |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | VirtualBox: TC-DC01 (PDC), TC-DC02, TC-LT-LAB01 + a second client or scheduled task as the "old device" |

## 1. The report

> *"Third day in a row I'm locked out when I arrive. I changed my password on Monday like you asked."* – Connie Springer, Account Executive

## 2. Environment / context

Connie changed her password on Monday. She also uses an old spare laptop at
home on VPN and has a mapped drive saved with credentials there.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

On a second lab machine: `cmdkey /add:TC-FS01 /user:TECHCORP\connie.springer /pass:<old password>` and a scheduled task that runs `Get-ChildItem \\TC-FS01\Departments` every 5 minutes. Eleven failures in 15 minutes → lockout (threshold 10).

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Is she locked, and since when? | `Get-ADUser connie.springer -Properties LockedOut, BadLogonCount, LastBadPasswordAttempt, PasswordLastSet` | Locked, many bad attempts, password set Monday | Something still uses the old password |
| 2 | Where do the bad attempts come from? | On the **PDC emulator** (`(Get-ADDomain).PDCEmulator`): `Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4740} \| Where-Object { $_.Properties[0].Value -eq 'connie.springer' } \| Select-Object TimeCreated, @{n='Source';e={$_.Properties[1].Value}}` | *Caller Computer Name* = the home laptop | Source found |
| 3 | Which protocol? | Event 4771 (Kerberos 0x18) / 4776 (NTLM) on the DCs | NTLM 4776 from the source | Saved credential / mapped drive, not an interactive logon |
| 4 | On the source device | `cmdkey /list`, Credential Manager, mapped drives, phone mail apps | Saved `TC-FS01` credential | Root cause |

## 5. Root cause

A saved credential with the old password retries in the background; each
retry is a bad password attempt counted against the account.

## 6. Resolution

1. Remove/update the saved credential on the source device (`cmdkey /delete:TC-FS01`).
2. Unlock: `Unlock-ADAccount connie.springer` (helpdesk delegation lets `wadm-` do it).
3. Do **not** reset her password – the new one is fine.

## 7. Verification

`BadLogonCount` stays at 0 over the next hour; no new 4740 events.

## 8. Prevention

- Password-change guidance in onboarding: phone mail, saved credentials, mapped drives with stored passwords.
- Lockout policy is self-healing (15 min) – most single lockouts need no ticket.

## 9. Skills practised

- Lockout source tracing on the PDC emulator (event 4740)
- Reading security events with `Get-WinEvent`

## 10. Related

- [user-accounts.md §3](../../03-windows-server/users-and-groups/user-accounts.md#3-password-and-lockout-policy)
- [ad-troubleshooting.md](../../03-windows-server/active-directory/ad-troubleshooting.md)
