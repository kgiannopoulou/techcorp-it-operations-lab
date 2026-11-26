# Office Floor Plan

| Field | Value |
|---|---|
| Document ID | DEP-REF-004 |
| Owner | IT Specialist |
| Status | Approved |
| Last reviewed | 2026-11-26 |
| Related requirements | BR-04, BR-05, BR-06, BR-07, BR-15, BR-23 |

## 1. Layout (not to scale, ~260 m²)

```text
 N ▲
 ┌───────────────────────────────────────────────────────────────────────────┐
 │  OPEN-PLAN WORK AREA                                        (AP01 ✶)      │
 │                                                                           │
 │   [01][02][03]   [04][05][06]   [07][08][09]                              │
 │   Dev pod          Dev / IT       Sales pod                               │
 │                                                                           │
 │   [10][11][12]   [13][14][15]   [16][17][18]         ┌──────────────────┐ │
 │   Sales/Mktg       Mgmt hot-desk  Support pod        │ PRINT AREA       │ │
 │                                                     │ TC-PRN01 (D-32)  │ │
 │                                       (AP02 ✶)      └──────────────────┘ │
 ├──────────────┬──────────────┬─────────────────┬──────────────┬───────────┤
 │ FINANCE      │ HR OFFICE    │ MEETING ROOM 1  │ MEETING      │ COMMS     │
 │ (lockable)   │ (lockable)   │ 8 seats         │ ROOM 2       │ ROOM      │
 │ [19][20][21] │ [22][23]     │ TC-MR-001       │ 4 seats      │ (locked,  │
 │ TC-PRN02     │              │                 │ TC-MR-002    │ ventilated│
 │ (D-33)       │              │                 │ interviews   │ 18U rack) │
 ├──────────────┴──────┬───────┴─────────────────┴──────────────┴───────────┤
 │ RECEPTION  [24]     │  CORRIDOR      (AP03 ✶)          │ KITCHEN          │
 │ Office Coordinator  │                                  │                  │
 └─────────────────────┴──── Main entrance ──────────────────────────────────┘

 [nn] = desk with dock + 2 monitors + wall drop D-nn      ✶ = ceiling Wi-Fi AP
```

## 2. Rooms

| Room | Seats | Purpose | IT equipment | Physical security |
|---|---:|---|---|---|
| Open-plan work area | 18 | Hot-desking for Dev, Sales/Marketing, Management, Support | Desks 01–18, TC-AP01, TC-AP02, TC-PRN01 | Office access badge |
| Finance office | 3 | Finance team, confidential paperwork | Desks 19–21, TC-PRN02 | Lockable door, clear-desk rule |
| HR office | 2 | HR, personnel files | Desks 22–23 | Lockable door, locked filing cabinet |
| Reception | 1 | Office Coordinator, visitor sign-in | Desk 24 | Visible from entrance |
| Meeting Room 1 | 8 | Client meetings, all-hands | TC-MR-001 video bar + 55″ display | – |
| Meeting Room 2 | 4 | Interviews, private calls | TC-MR-002 video bar + 55″ display | – |
| Comms room | – | Network and server rack | Rack, TC-FW01, TC-SW01, TC-HV01, TC-NAS01, TC-UPS01 | **Locked; key held by IT + Operations Manager only**; dedicated power circuit; split-unit A/C |
| Kitchen | – | Breaks | 2 spare drops (future digital signage) | – |

## 3. Desk allocation

24 desks for 20 people leaves 4 desks for growth and visitors. The 12 hybrid
staff hot-desk in the open plan; departments have *home pods* so teams sit
together, but any person can use any open-plan desk because every desk is
identical (same dock and monitors).

| Desks | Home pod | Notes |
|---|---|---|
| 01–06 | Software Development + IT | Desk 06 is the IT Specialist's fixed desk (next to comms corridor) |
| 07–12 | Sales & Marketing | |
| 13–15 | Management hot desks | CEO and Operations Manager |
| 16–18 | Customer Support | Fixed desks, headsets, near print area |
| 19–21 | Finance | Fixed, inside Finance office |
| 22–23 | HR | Fixed, inside HR office |
| 24 | Reception | Office Coordinator |

## 4. Wi-Fi placement rationale

Three ceiling APs on PoE give two-AP overlap across the open plan, which
carries ~80 % of the people:

| AP | Location | Covers |
|---|---|---|
| TC-AP01 | Open plan, north-east ceiling | Desks 01–09, print area |
| TC-AP02 | Open plan, south-centre ceiling | Desks 10–18, Finance, HR |
| TC-AP03 | Corridor ceiling near Meeting Room 1 | Meeting rooms, reception, kitchen |

Channel plan (5 GHz, 40 MHz): AP01 ch 36, AP02 ch 52, AP03 ch 149;
2.4 GHz kept on 20 MHz channels 1 / 6 / 11. A walk-through survey is
repeated after furniture is installed (Phase 1).
