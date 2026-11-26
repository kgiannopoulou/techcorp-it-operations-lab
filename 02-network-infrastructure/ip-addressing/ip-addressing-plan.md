# IP Addressing Plan

| Field | Value |
|---|---|
| Document ID | NET-REF-002 |
| Owner | IT Specialist |
| Status | Approved (design) – to be built in Phase 1 |
| Last reviewed | 2026-11-26 |
| Related requirements | BR-05, BR-09, BR-15, BR-19 |

Source data: [vlan-subnets.csv](vlan-subnets.csv). Device addresses come from
[hardware-inventory.csv](../../01-office-deployment/equipment-inventory/hardware-inventory.csv);
CI checks that every static IP sits inside its VLAN's subnet and is unique.

## 1. Design rules

1. **Address block:** `10.10.0.0/16` for the whole company. One summary route
   for VPN clients and any future site.
2. **The third octet equals the VLAN ID**: `10.10.<VLAN>.0/24`. Seeing
   `10.10.40.x` you immediately know it is a printer.
3. **`.1` is always the default gateway** (firewall sub-interface).
4. **Low addresses are static, the middle is DHCP**: `.1–.49` static /
   reservations, `.50–.240` DHCP pool (staff), `.241–.254` reserved.
5. **Avoid `192.168.0.0/24` and `192.168.1.0/24`** – they are the default on
   most home routers and would collide with VPN users' home networks.
6. `/24` everywhere is deliberately simple: wasteful in theory, but private
   space is plentiful and one person must operate it. Right-sizing with
   VLSM is practised separately in `subnetting/` during Phase 1.

## 2. VLANs and subnets

| VLAN | Name | Subnet | Gateway | DHCP | Usable hosts | Purpose |
|---:|---|---|---|---|---:|---|
| 10 | MGMT | 10.10.10.0/24 | 10.10.10.1 | DCs via relay, `.100–.150` | 254 | Switch, APs, UPS, iDRAC, IT service port |
| 20 | STAFF | 10.10.20.0/24 | 10.10.20.1 | DCs via relay, `.50–.240` | 254 | Laptops (wired and SSID `TechCorp`), meeting rooms |
| 30 | SERVERS | 10.10.30.0/24 | 10.10.30.1 | none – static | 254 | TC-HV01, TC-DC01/02, TC-FS01, TC-NAS01 |
| 40 | PRINTERS | 10.10.40.0/24 | 10.10.40.1 | none – static | 254 | TC-PRN01, TC-PRN02 |
| 50 | GUEST | 10.10.50.0/24 | 10.10.50.1 | Firewall, `.50–.250` | 254 | SSID `TechCorp-Guest`, internet only, client isolation |
| 60 | VPN (virtual) | 10.10.60.0/24 | 10.10.60.1 | Firewall VPN pool | 254 | Remote-access VPN clients |
| 999 | PARKING | – | – | – | – | Unused ports; no routing |
| WAN | ISP | 203.0.113.8/29 (example) | 203.0.113.9 | static | 5 | Public static IPs (RFC 5737 documentation range) |

## 3. Static assignments

| Device | VLAN | IP address | Notes |
|---|---:|---|---|
| TC-FW01 (LAN gateway for each VLAN) | 10/20/30/40/50 | 10.10.x.1 | Sub-interfaces on one trunk |
| TC-FW01 WAN1 | WAN | 203.0.113.10/29 | Fibre via ISP ONT (bridge mode) |
| TC-FW01 WAN2 | WAN | DHCP (CGNAT) | 4G/5G failover |
| TC-SW01 | 10 | 10.10.10.2 | Management SVI |
| TC-UPS01 | 10 | 10.10.10.5 | Network card |
| TC-AP01 / AP02 / AP03 | 10 | 10.10.10.11 / .12 / .13 | Management IP; SSIDs bridged to VLAN 20/50 |
| TC-HV01 iDRAC/iLO | 10 | 10.10.10.20 | Out-of-band management |
| TC-HV01 (host OS) | 30 | 10.10.30.10 | Hyper-V host |
| TC-DC01 | 30 | 10.10.30.11 | AD DS, DNS, DHCP (primary) |
| TC-DC02 | 30 | 10.10.30.12 | AD DS, DNS, DHCP (failover partner) |
| TC-FS01 | 30 | 10.10.30.20 | File server, DFS namespace |
| TC-NAS01 | 30 | 10.10.30.30 | Backup target |
| TC-PRN01 | 40 | 10.10.40.10 | Open-plan MFP |
| TC-PRN02 | 40 | 10.10.40.11 | Finance printer |
| TC-MR-001 / TC-MR-002 | 20 | 10.10.20.21 / .22 | DHCP reservations (meeting-room kits) |

## 4. DNS and DHCP options

| Option | VLAN 10 / 20 | VLAN 50 (guest) |
|---|---|---|
| 003 Router | 10.10.x.1 | 10.10.50.1 |
| 006 DNS servers | 10.10.30.11, 10.10.30.12 | 10.10.50.1 (firewall resolver → public DNS) |
| 015 DNS domain | `corp.techcorp.example` | – |
| Lease time | 8 days (laptops) | 4 hours |

DHCP for VLAN 10 and 20 is provided by the domain controllers with **DHCP
failover** (load-balance 50/50); the firewall relays requests (`ip helper`
equivalent). Guests never see internal DNS.

## 5. Inter-VLAN policy (summary)

Default **deny**; only the flows below are allowed. Detailed rules are built
and tested in Phase 1 (`firewall/`).

| From \ To | MGMT 10 | STAFF 20 | SERVERS 30 | PRINTERS 40 | GUEST 50 | Internet |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| **MGMT 10** | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ (updates) |
| **STAFF 20** | ❌ (IT laptop only) | ✅ | ✅ AD/DNS/SMB/DHCP | ✅ print ports | ❌ | ✅ |
| **SERVERS 30** | ✅ (SNMP/UPS) | ✅ (replies) | ✅ | ✅ | ❌ | ✅ (updates, backup) |
| **PRINTERS 40** | ❌ | ❌ | ✅ scan-to-SMB, SMTP relay | ✅ | ❌ | ✅ (scan-to-e-mail only) |
| **GUEST 50** | ❌ | ❌ | ❌ | ❌ | ❌ (isolation) | ✅ |
| **VPN 60** | ❌ (IT only) | ❌ | ✅ AD/DNS/SMB | ✅ | ❌ | – (split tunnel) |
