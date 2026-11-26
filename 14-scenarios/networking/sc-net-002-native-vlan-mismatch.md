# SC-NET-002: Switch log full of native VLAN mismatch messages

| Field | Value |
|---|---|
| Scenario ID | SC-NET-002 |
| Category | Networking |
| Difficulty | ⭐⭐ |
| Priority (if real) | P3 – no user impact yet |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | [Packet Tracer lab](../../02-network-infrastructure/packet-tracer-lab/) / VirtualBox lab |

## 1. The report

> *"The switch console keeps printing %CDP-4-NATIVE_VLAN_MISMATCH every minute."* – Eren Yeager, IT Specialist – noticed during a health check

## 2. Environment / context

Trunk between SW1-LAB Gi0/1 and the neighbouring device. Users still work, but untagged traffic could leak between VLAN 1 and VLAN 999.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

Lab build: add a second 2960 (`SW2-LAB`) trunked to SW1-LAB, then set `switchport trunk native vlan 1` on SW2 only (CDP runs between the two switches).

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Logs | `show logging` | %CDP-4-NATIVE_VLAN_MISMATCH … (1) … (999) | The two ends disagree |
| 2 | Trunk detail | `show interfaces trunk` | Native vlan 1 on SW2, 999 on SW1 | SW2 is wrong |
| 3 | Standard | `vlan-configuration.md` | Native must be 999 | Confirms the intended value |

## 5. Root cause

The native VLAN is configured differently on the two ends of a trunk, so untagged frames from one VLAN arrive in a different VLAN on the other side.

## 6. Resolution

On SW2-LAB: `interface Gi0/1` → `switchport trunk native vlan 999`.

## 7. Verification

The log messages stop; `show interfaces trunk` shows native 999 on both switches.

## 8. Prevention

- Native VLAN 999 on all trunks, recorded in the CI-validated port plan CSV.
- Never use VLAN 1 for anything.

## 9. Skills practised

- 802.1Q native VLAN and the VLAN-hopping risk
- CDP as a troubleshooting tool

## 10. Related

- [switch-configuration.md](../../02-network-infrastructure/switching/switch-configuration.md)
