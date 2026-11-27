# SC-HW-002: Only one of the two monitors works at desk 11

| Field | Value |
|---|---|
| Scenario ID | SC-HW-002 |
| Category | Hardware |
| Difficulty | ⭐ |
| Priority (if real) | P4 – inconvenience, workaround exists |
| Status | Designed – expected investigation written; **not yet performed** (needs real hardware – cannot be simulated in VirtualBox) |
| Lab | Physical: any USB-C dock + two monitors |

## 1. The report

> *"At desk 11 the second screen just says 'No signal'. At desk 4 yesterday both worked."* – Reiner Braun, Account Executive

## 2. Environment / context

Hot desk 11; dock `TC-DCK-011`; Reiner's laptop TC-LT-010 works with two monitors at other desks.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

Either the dock at desk 11 has older firmware without DisplayPort MST support, or the laptop's cable was plugged into the dock's USB-C *data-only* port.

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Same laptop, other desk | Desk 4 | Two monitors work | Laptop/driver OK – the desk is the variable |
| 2 | Same desk, other laptop (spare) | TC-LT-021 at desk 11 | Also one monitor | Fault is in desk 11's kit |
| 3 | Monitor itself | Swap the two monitors' cables at the dock | "No signal" follows the dock port | Monitor OK |
| 4 | Dock firmware | Vendor dock tool on the laptop | Version older than the fleet baseline | Root cause |
| 5 | Inventory | `hardware-inventory.csv` row TC-DCK-011 | Installed from an older batch | Explains why only this desk |

## 5. Root cause

Dock firmware below the fleet baseline – the second DisplayPort output needs
the MST update.

## 6. Resolution

Update the dock firmware with the vendor tool (laptop on AC, dock connected),
power-cycle the dock.

## 7. Verification

Both monitors extend the desktop at 1080p with TC-LT-010 and with a spare.

## 8. Prevention

Quarterly desk check ([desks-and-meeting-rooms.md §1](../../04-endpoint-management/peripherals/desks-and-meeting-rooms.md#1-hot-desks-24))
includes the dock firmware version; record it per dock in the asset register (Phase 11).

## 9. Skills practised

- Swap-one-variable-at-a-time hardware troubleshooting
- Asset records as a troubleshooting tool
