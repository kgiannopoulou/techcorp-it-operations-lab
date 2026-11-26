# SC-NET-003: A visitor's laptop can open the internal file server

| Field | Value |
|---|---|
| Scenario ID | SC-NET-003 |
| Category | Networking |
| Difficulty | ⭐⭐⭐ |
| Priority (if real) | P1 – security incident |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | [Packet Tracer lab](../../02-network-infrastructure/packet-tracer-lab/) / VirtualBox lab |

## 1. The report

> *"During the client demo, the visitor's laptop listed our Departments share in File Explorer."* – Jean Kirstein, Sales & Marketing Manager

## 2. Environment / context

The visitor plugged into the meeting-room table port (D-26) instead of using guest Wi-Fi. Guest Wi-Fi itself is isolated correctly.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

The meeting-room table port is an access port in VLAN 20 (staff), as the Milestone 3 port plan specified. Packet Tracer version: move Fa0/6 to VLAN 20.

> This scenario exposed a real design flaw – the fix is already applied to the production design as change NET-CHG-002. The lab reproduces the *old* setting.

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Visitor IP | `ipconfig` | 10.10.20.x – a STAFF address | The visitor is on the staff VLAN |
| 2 | Port | `show interfaces Fa0/6 switchport` | Access VLAN 20 | The port design allows it |
| 3 | Firewall log | `pfSense firewall log` | SMB passed from 10.10.20.x | Rules worked as designed – wrong VLAN |
| 4 | Policy | `firewall-rules.md` | STAFF → TC-FS01:445 allowed | Physical access = network access |

## 5. Root cause

A port that visitors can physically reach was placed in the trusted staff VLAN. Segmentation is only as good as the port assignment.

## 6. Resolution

1. Move the meeting-room **table ports** (D-26, D-28) to VLAN 50 in `switch-port-plan.csv` and on the switch.
2. Treat it as a security incident: check TC-FS01 access logs for the visitor's IP and record it in `16-reports/incidents`.

## 7. Verification

The visitor laptop now gets 10.10.50.x; `Test-TechCorpNetwork.ps1 -VlanProfile Guest` passes (all internal targets Filtered).

## 8. Prevention

- Design rule: any port a visitor can reach = guest VLAN.
- Phase 9: 802.1X / MAB so only company devices land in VLAN 20.

## 9. Skills practised

- Thinking like an attacker about physical access
- Incident handling basics

## 10. Related

- [firewall-rules.md](../../02-network-infrastructure/firewall/firewall-rules.md)
- [cabling-plan.md](../../01-office-deployment/network-installation/cabling-plan.md)
