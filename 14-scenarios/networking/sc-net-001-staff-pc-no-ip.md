# SC-NET-001: Nobody in the open plan can get on the network after a switch change

| Field | Value |
|---|---|
| Scenario ID | SC-NET-001 |
| Category | Networking |
| Difficulty | ⭐⭐ |
| Priority (if real) | P2 – one department cannot work |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | [Packet Tracer lab](../../02-network-infrastructure/packet-tracer-lab/) / VirtualBox lab |

## 1. The report

> *"Since lunchtime my laptop says 'No internet'. Reiner has the same problem."* – Connie Springer, Sales & Marketing

## 2. Environment / context

Several staff on desk docks (VLAN 20). Wi-Fi users on SSID `TechCorp` are also affected. MGMT and SERVERS still work. A switch change was made at 12:30 to add a new AP port.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

On the trunk to the router/firewall: `switchport trunk allowed vlan 10,30,40,50` – VLAN 20 has been dropped (the allowed list was retyped without the `add` keyword).

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Client IP config | `ipconfig /all` | 169.254.x.x (APIPA) | No DHCP lease |
| 2 | Port and VLAN | `show interfaces Fa0/1 switchport` | Access VLAN 20, up | Access side is fine |
| 3 | Trunk | `show interfaces trunk` | VLAN 20 missing from 'allowed and active' | DHCP Discover never reaches the gateway |
| 4 | Recent changes | `show logging` | Configuration change at 12:30 | The change caused it |

## 5. Root cause

VLAN 20 was removed from the trunk's allowed list because `switchport trunk allowed vlan <list>` **replaces** the list instead of adding to it.

## 6. Resolution

1. `interface Gi0/1` → `switchport trunk allowed vlan add 20` (or set the full list again).
2. On clients: `ipconfig /renew`.

## 7. Verification

`show interfaces trunk` lists 10,20,30,40,50; `Test-TechCorpNetwork.ps1` from a STAFF client passes the IP, gateway and DNS tests.

## 8. Prevention

- Always use `switchport trunk allowed vlan add|remove`.
- Take `copy running-config flash:backup-<date>.cfg` before changes and diff afterwards.
- Change management: switch changes outside business hours.

## 9. Skills practised

- Trunk allowed lists, `add` vs replace
- DHCP DORA and APIPA
- Reading `show interfaces trunk`

## 10. Related

- [vlan-configuration.md](../../02-network-infrastructure/vlans/vlan-configuration.md)
- [dhcp-configuration.md](../../02-network-infrastructure/dhcp/dhcp-configuration.md)
