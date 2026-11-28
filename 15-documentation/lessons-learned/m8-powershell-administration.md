# Lessons Learned: Milestone 8 – PowerShell Administration

| Field | Value |
|---|---|
| Document ID | DOC-LL-004 |
| Related phase / scenario | Phase 7 (M8), SC-PS-001 … SC-PS-005 |
| Date | 2026-11-28 |

## What happened

Wrote the administrative scripts one IT person needs every week: joiner and
leaver, stale-account review, password-expiry reminders, inventory/warranty
report, server health, service-port test, retention clean-up and a daily
check that combines them into one page. M8 was done before M7 (Intune and
Conditional Access) on request.

The difference to the M4–M6 scripts is **testing**: the rules moved into a
shared module of small functions with the clock passed in (`-Now`), and
every script has Pester tests – unit tests for the rules, script tests with
Active Directory, Graph and Exchange Online mocked, and tests of the
standards themselves.

## What went well

- Making time a parameter turned "does the 7-day reminder fire on the right
  day?" and "is the firewall's warranty flagged 90 days before 2030-02-15?"
  into ordinary tests instead of waiting for the date.
- Mocking AD in the leaver test made the *order* of the ten changes
  testable – the property that actually protects the mailbox.
- Running the read-only scripts on my own PC (health check, live inventory,
  port test against a local listener) found real behaviour – a pending
  reboot, an updater service that stops by design – before any lab exists.

## What went wrong / was harder than expected

| Problem | Found when | Change |
|---|---|---|
| The first password-expiry design assumed everybody's password expires – the domain policy says never (NIST) | Writing the expiry rules against user-accounts.md | **PS-CHG-002** – admin accounts only, owner's mailbox, AD's computed expiry |
| A joiner account created weeks early is enabled with a known password | Designing the onboarding steps | **PS-CHG-001** – created disabled until the start date |
| `Measure-Object` on an empty list has no `Sum` under `Set-StrictMode` | Clean-up script on a folder with no old files | Plain loop; regression test with an empty selection |
| `Split-Path -Parent 'C:'` throws instead of returning empty | Testing the drive-root refusal | `[IO.Path]::GetPathRoot()` |
| `@($list)` of a generic `List` inside an `[ordered]@{}` literal fails on Windows PowerShell 5.1 ("Argument types do not match") | Inventory report on 5.1 | `.ToArray()`; CI now also runs the tests on Windows PowerShell 5.1 |
| Formatting a `[double]` from `Measure-Object -Maximum` with `{0:D3}` fails | Employee ID in the onboarding plan | Cast to `[int]` |
| A script that ends without `exit` leaves `$LASTEXITCODE` from whatever ran before | Writing the exit-code tests | Every script ends with an explicit `exit` |
| The PC's Greek culture prints dates and decimals differently | Running the scripts locally | Invariant culture for parsing; `w32tm` offsets accept `,` and `.` |
| Pester 5 is not on the lab PC yet – Windows ships Pester 3.4, whose syntax is different | Running the tests | Tests run in CI on Linux and Windows; documented install command |

## What I learned (technical)

- `msDS-UserPasswordExpiryTimeComputed` already includes fine-grained password policies – never re-implement policy logic.
- `lastLogonTimestamp` replicates only every 9–14 days, so stale thresholds below 14 days are noise (enforced by `ValidateRange`).
- Mark of the Web makes `RemoteSigned` refuse scripts extracted from a browser download (SC-PS-001).
- Scheduled tasks run in `C:\Windows\System32` with the task account's environment – destructive scripts must take mandatory, literal paths (SC-PS-005).
- Pester mocks prove *what* a script asks AD to do, not that AD accepts it – the lab run is still needed.

## What I will do differently

| Action | Where it is documented | Done |
|---|---|---|
| Keep rules in testable functions with an injectable clock from the first version of a script | 07-powershell README – script standards | ☑ |
| Pre-flight check of Graph/EXO connections before the leaver's first change | SC-PS-003 | ☐ |
| Alert on a *missing* daily report, not only on its exit code | SC-PS-001 → M12 monitoring | ☐ |
| Run every M8 script against the lab domain and keep the CSV/HTML as evidence | 16-reports, M5 lab | ☐ |
| Intune, MFA and Conditional Access | M7 | ☐ |
