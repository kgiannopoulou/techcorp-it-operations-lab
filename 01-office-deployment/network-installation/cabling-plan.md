# Structured Cabling, Rack and Patching Plan

| Field | Value |
|---|---|
| Document ID | DEP-REF-005 |
| Owner | IT Specialist (installation by cabling contractor) |
| Status | Approved |
| Last reviewed | 2026-11-26 |
| Related requirements | BR-04, BR-05, BR-19, BR-23 |

## 1. Cabling standard

| Item | Specification |
|---|---|
| Cable | Cat6 U/UTP, LSZH jacket, solid copper |
| Termination | T568B at both ends, keystone jacks at wall, 2× 24-port Cat6 patch panels in rack |
| Max permanent link | 90 m (longest run in this office ≈ 35 m) |
| Testing | Every drop certified with a cable certifier; report attached to handover (Cat6 permanent link) |
| Labelling | Same label at both ends: wall plate `D-NN` ↔ patch-panel port `PP1-NN` / `PP2-NN` |
| Patch cords | 0.5 m (rack, colour-coded), 2 m (desk) |
| Containment | Ceiling tray to comms room, floor boxes under desk pods |

### Patch-cord colours (rack)

| Colour | Use |
|---|---|
| Blue | Staff desks and meeting rooms (VLAN 20) |
| Yellow | Wi-Fi APs (trunks) |
| Green | Printers (VLAN 40) |
| Red | Firewall / uplinks |
| Black | Servers and NAS |
| Grey | Management (iDRAC, UPS, switch management) |

## 2. Drop schedule (44 drops)

| Drops | Location | Qty | Use | Patched on day 1 |
|---|---|---:|---|:-:|
| D-01 – D-18 | Open-plan desks 01–18 | 18 | Dock | ✅ |
| D-19 – D-21 | Finance desks 19–21 | 3 | Dock | ✅ |
| D-22 – D-23 | HR desks 22–23 | 2 | Dock | ✅ |
| D-24 | Reception desk 24 | 1 | Dock | ✅ |
| D-25 – D-26 | Meeting Room 1 (video bar D-25 / table port D-26) | 2 | Room kit (VLAN 20) / visitor laptop (**VLAN 50**) | ✅ |
| D-27 – D-28 | Meeting Room 2 (video bar D-27 / table port D-28) | 2 | Room kit (VLAN 20) / visitor laptop (**VLAN 50**) | ✅ |
| D-29 – D-31 | Ceilings: AP01, AP02, AP03 | 3 | PoE+ Wi-Fi | ✅ |
| D-32 | Print area | 1 | TC-PRN01 | ✅ |
| D-33 | Finance office | 1 | TC-PRN02 | ✅ |
| D-34 – D-36 | Open plan (spare) | 3 | Future desks | ❌ |
| D-37 | Finance (spare) | 1 | Future | ❌ |
| D-38 | HR (spare) | 1 | Future | ❌ |
| D-39 | Reception (spare) | 1 | Visitor screen / future | ❌ |
| D-40 | Meeting Room 1 (spare) | 1 | Future | ❌ |
| D-41 – D-42 | Kitchen | 2 | Digital signage (future) | ❌ |
| D-43 – D-44 | Corridor ceiling | 2 | Future CCTV / door access (PoE) | ❌ |

33 drops are active on day one, 11 are spare (≈ 25 % growth capacity – it is
far cheaper to pull extra cable during the fit-out than afterwards).

Drops D-01 – D-24 terminate on **PP1-01 – PP1-24**; D-25 – D-44 on
**PP2-01 – PP2-20** (PP2-21 – PP2-24 unused).

## 3. Rack elevation (18U, 800 mm deep, comms room)

| U | Device | Notes |
|---|---|---|
| 18 | Blank / ventilation | |
| 17 | Patch panel PP1 (D-01 – D-24) | |
| 16 | Horizontal cable manager | |
| 15 | Patch panel PP2 (D-25 – D-44) | |
| 14 | Horizontal cable manager | |
| 13 | Blank | Growth |
| 12 | ISP ONT / router (shelf) | Bridge mode → TC-FW01 WAN |
| 11 | Shelf: 4G/5G modem | → TC-FW01 WAN2 |
| 10 | TC-FW01 firewall (shelf) | |
| 9 | Horizontal cable manager | |
| 8 | TC-SW01 48-port PoE+ switch | |
| 7 | Blank | Space for a second host later |
| 6 | Blank | Airflow |
| 5 | TC-HV01 server (1U, rails) | |
| 4 | Blank | Airflow |
| 3 | TC-NAS01 (1U) | |
| 1–2 | TC-UPS01 (2U) | Heavy item at the bottom |
| – | Vertical PDU (rear) | Fed from UPS |

Power: dedicated 16 A circuit for the comms room. Everything in the rack runs
through TC-UPS01 except the A/C. Expected load ≈ 450 W → ~20 min runtime.

## 4. Switch port plan – TC-SW01

| Ports | Connected to | Mode | VLAN(s) | Notes |
|---|---|---|---|---|
| 1–24 | PP1-01 – PP1-24 (desks D-01 – D-24) | Access | 20 | PortFast, BPDU guard, storm control |
| 25, 27 | PP2-01, PP2-03 (meeting-room video bars) | Access | 20 | PoE |
| 26, 28 | PP2-02, PP2-04 (meeting-room table ports) | Access | **50** | Visitors plug in here – guest VLAN (change NET-CHG-002) |
| 29–31 | PP2-05 – PP2-07 (AP01–03) | Trunk | Native 10; tagged 20, 50 | PoE+ |
| 32–33 | PP2-08 – PP2-09 (PRN01, PRN02) | Access | 40 | |
| 34–40 | – (spare) | Access, **shutdown** | 999 (parking) | Enabled on request |
| 41 | TC-FW01 LAN | Trunk | 10, 20, 30, 40, 50 | Router-on-a-stick |
| 42–43 | TC-HV01 NIC1 + NIC2 (SET team) | Trunk | 30 (+10 for host mgmt) | |
| 44 | TC-HV01 iDRAC/iLO | Access | 10 | |
| 45–46 | TC-NAS01 (LACP) | Access | 30 | |
| 47 | TC-UPS01 network card | Access | 10 | |
| 48 | IT service port (comms room) | Access | 10 | For console laptop |

Port-to-drop mapping makes tracing trivial: **desk drop D-07 = PP1-07 = switch
port 7**. The live configuration and its verification are built in Phase 1
(`02-network-infrastructure/switching`).
