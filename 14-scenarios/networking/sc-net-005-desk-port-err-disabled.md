# SC-NET-005: Desk port dead after a user brought in a mini switch

| Field | Value |
|---|---|
| Scenario ID | SC-NET-005 |
| Category | Networking |
| Difficulty | ⭐ |
| Priority (if real) | P3 – one user |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | [Packet Tracer lab](../../02-network-infrastructure/packet-tracer-lab/) / VirtualBox lab |

## 1. The report

> *"I plugged in a small switch so I could connect my laptop and a demo device. Now nothing works at this desk."* – Reiner Braun, Sales & Marketing

## 2. Environment / context

Desk D-02 (switch port 2). Other desks are fine.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

Connect a second switch to Fa0/2 in Packet Tracer – BPDU guard err-disables the port.

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Link | `Get-NetAdapter` | Disconnected | Physical / layer-2 problem |
| 2 | Port state | `show interfaces status err-disabled` | Fa0/2 err-disabled, reason bpduguard | Protection triggered |
| 3 | Log | `show logging` | %SPANTREE-2-BLOCK_BPDUGUARD | A switch BPDU was received |

## 5. Root cause

BPDU guard shut the port because another switch was connected to an access port – working as designed.

## 6. Resolution

1. Remove the mini switch.
2. `interface Fa0/2` → `shutdown` → `no shutdown` (or wait 300 s for errdisable recovery on TC-SW01).
3. If the user needs two ports: raise a request for the spare drop – never an unmanaged switch.

## 7. Verification

The port is `connected` in VLAN 20 and the laptop gets a lease.

## 8. Prevention

- Acceptable Use Policy: no personal network equipment (Phase 12).
- errdisable recovery is already configured on TC-SW01.

## 9. Skills practised

- STP, BPDU guard, err-disabled recovery

## 10. Related

- [switch-configuration.md](../../02-network-infrastructure/switching/switch-configuration.md)
