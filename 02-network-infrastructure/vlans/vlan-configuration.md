# VLAN Design and Configuration

| Field | Value |
|---|---|
| Document ID | NET-PRC-001 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved when the lab steps below have been executed and evidenced |
| Last reviewed | 2026-11-26 |
| Related requirements | BR-05, BR-15 |

## Purpose

Separate traffic by **trust level** so that a guest phone, a compromised
printer or a visitor's laptop cannot reach staff devices or servers (BR-15).

## 1. VLAN table

Source: [vlan-subnets.csv](../ip-addressing/vlan-subnets.csv).

| VLAN | Name | Subnet | Members | Trust |
|---:|---|---|---|---|
| 10 | VLAN10-MGMT | 10.10.10.0/24 | Switch SVI, AP management, UPS, iDRAC, IT service port | High – admins only |
| 20 | VLAN20-STAFF | 10.10.20.0/24 | Desk docks, meeting-room video bars, Wi-Fi `TechCorp` | Medium |
| 30 | VLAN30-SERVERS | 10.10.30.0/24 | TC-HV01, DCs, file server, NAS | High |
| 40 | VLAN40-PRINTERS | 10.10.40.0/24 | TC-PRN01, TC-PRN02 | Low (IoT-like firmware) |
| 50 | VLAN50-GUEST | 10.10.50.0/24 | Wi-Fi `TechCorp-Guest`, meeting-room table ports D-26/D-28 | **Untrusted** |
| 999 | VLAN999-PARKING | – | All unused ports, trunk native VLAN | None – black hole |

**VLAN 1 is never used.** It is the default on every switch, so anything
plugged into a default port would land there; using a parking VLAN instead
means an unconfigured port reaches nothing.

## 2. Concepts in one table

| Term | Meaning at TechCorp |
|---|---|
| Access port | Belongs to one VLAN, frames untagged – desks (20), printers (40) |
| Trunk port | Carries several VLANs with 802.1Q tags – firewall uplink, APs, Hyper-V host |
| Native VLAN | The VLAN sent **untagged** on a trunk. Set to 999 on the firewall/host trunks (stops VLAN-hopping); 10 on AP trunks because APs fetch their management IP untagged |
| Allowed VLANs | Explicit list per trunk – a trunk never carries "all" |
| SVI | Switch Virtual Interface – the switch's own IP, only in VLAN 10 |
| Router-on-a-stick | The firewall has one physical LAN port with a sub-interface (and gateway) per VLAN |

## 3. Production configuration – TC-SW01 (Cisco IOS-XE)

The full configuration is generated from
[switch-port-plan.csv](../switching/switch-port-plan.csv) into
[tc-sw01.cfg](../switching/tc-sw01.cfg). The VLAN part:

```text
vtp mode transparent
vlan 10
 name VLAN10-MGMT
vlan 20
 name VLAN20-STAFF
vlan 30
 name VLAN30-SERVERS
vlan 40
 name VLAN40-PRINTERS
vlan 50
 name VLAN50-GUEST
vlan 999
 name VLAN999-PARKING
!
interface Gi1/0/41
 description UPLINK TC-FW01 LAN trunk
 switchport mode trunk
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,30,40,50
 switchport nonegotiate
```

`vtp mode transparent` – with one switch there is nothing to synchronise, and
transparent mode removes the classic risk of a second switch wiping the VLAN
database. `switchport nonegotiate` turns off DTP so a user cannot negotiate a trunk.

## 4. Production configuration – TC-FW01 (pfSense)

1. **Interfaces → VLANs → Add** – parent interface = LAN port (`igc1` on a
   Netgate 4200), create tags 10, 20, 30, 40, 50 with descriptions matching the
   VLAN names.
2. **Interfaces → Assignments** – add each VLAN as an interface, rename them
   `MGMT`, `STAFF`, `SERVERS`, `PRINTERS`, `GUEST`.
3. For each interface: **Enable**, IPv4 = Static, address `10.10.<VLAN>.1/24`.
4. The physical parent `igc1` itself carries no IP address (its untagged
   traffic would be the native VLAN 999 – nothing).

*Expected result:* **Status → Interfaces** shows five VLAN interfaces up with
the `.1` addresses.

## 5. Lab procedure

The home lab has no physical switch, so VLANs are practised in two places
(see [lab-environment.md](../topology/lab-environment.md)):

| What | Where |
|---|---|
| VLAN database, access/trunk ports, native VLAN, allowed lists | Cisco Packet Tracer – [packet-tracer-lab](../packet-tracer-lab/) |
| Segmentation enforced by the firewall with real OS clients | VirtualBox: each VLAN is an internal network (`tc-vlan10`…`tc-vlan50`) connected to its own pfSense interface |

## 6. Verification

| Check | Command | Expected |
|---|---|---|
| VLANs exist with names | `show vlan brief` | 10, 20, 30, 40, 50, 999 active; ports listed against each |
| Trunks correct | `show interfaces trunk` | Gi1/0/41 native 999, allowed 10,20,30,40,50 |
| Port in right VLAN | `show interfaces Gi1/0/7 switchport` | Access mode VLAN 20 |
| Client gets right subnet | `ipconfig /all` on a laptop on desk 07 | 10.10.20.x, gateway 10.10.20.1 |

## 7. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Client gets 169.254.x.x | Port in wrong/parking VLAN, or VLAN not allowed on the trunk | `show interfaces Gx switchport`, add VLAN to trunk allowed list |
| One VLAN works, another doesn't | VLAN missing from allowed list or not created on the switch | `show interfaces trunk` → "VLANs allowed and active" |
| `%CDP-4-NATIVE_VLAN_MISMATCH` | Native VLAN differs between the two ends of a trunk | Set the same native VLAN on both sides |
| AP online but SSID clients get no IP | AP trunk missing VLAN 20 or 50 | Check allowed list on Gi1/0/29–31 |

## Evidence

To be added from the lab: `show vlan brief`, `show interfaces trunk`, pfSense
interface status → `15-documentation/screenshots/phase-01/`.
