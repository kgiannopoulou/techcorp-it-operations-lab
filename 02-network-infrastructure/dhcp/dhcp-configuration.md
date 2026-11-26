# DHCP Configuration

| Field | Value |
|---|---|
| Document ID | NET-PRC-004 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved after lab execution |
| Last reviewed | 2026-11-26 |
| Related requirements | BR-04, BR-05, BR-15, BR-19 |

## Purpose

Give every client in MGMT, STAFF and GUEST an address, gateway, DNS servers and
domain suffix automatically; keep servers and printers on documented static IPs.

## 1. Scope design

DHCP server: **TC-FW01** (pfSense, Kea DHCP backend) on each VLAN interface.

| VLAN | Pool | Excluded / static | Gateway (opt 3) | DNS (opt 6) – now | DNS – after Phase 2 | Domain (opt 15) | Lease |
|---|---|---|---|---|---|---|---|
| 10 MGMT | 10.10.10.100 – .150 | .1 – .49 static | 10.10.10.1 | 10.10.10.1 | 10.10.30.11, .12 | corp.techcorp.example | 1 day |
| 20 STAFF | 10.10.20.50 – .240 | .1 – .49 static/reserved | 10.10.20.1 | 10.10.20.1 | 10.10.30.11, .12 | corp.techcorp.example | 8 days |
| 30 SERVERS | – (no DHCP) | all static | – | – | – | – | – |
| 40 PRINTERS | – (no DHCP) | all static | – | – | – | – | – |
| 50 GUEST | 10.10.50.50 – .250 | – | 10.10.50.1 | 10.10.50.1 | 10.10.50.1 (never internal DNS) | – | 4 hours |

**Capacity check (STAFF):** 22 laptops × 2 interfaces (dock NIC + Wi-Fi) + 2
meeting rooms ≈ 46 leases against a 191-address pool → 24 % utilisation.
Personal phones join the guest SSID, not STAFF.

### Static mappings (reservations)

| Device | VLAN | MAC | IP |
|---|---:|---|---|
| TC-MR-001 video bar | 20 | *(recorded at install)* | 10.10.20.21 |
| TC-MR-002 video bar | 20 | *(recorded at install)* | 10.10.20.22 |

## 2. Procedure – pfSense

1. **System → Advanced → Networking → DHCP Options**: confirm *Server Backend* = **Kea DHCP**.
2. **Services → DHCP Server → STAFF**:
   - Enable; Address pool `10.10.20.50` – `10.10.20.240`.
   - DNS servers: leave empty (pfSense hands out its own interface IP while the
     DNS Resolver is the only DNS server). In Phase 2 enter `10.10.30.11`, `10.10.30.12`.
   - Domain name `corp.techcorp.example`; default lease time `691200` s (8 days).
   - NTP server `10.10.20.1`.
   - Add the two static mappings above.
3. Repeat for **MGMT** (pool `.100–.150`, lease `86400`) and **GUEST**
   (pool `.50–.250`, lease `14400`, *no* domain name).
4. Leave DHCP **disabled** on SERVERS and PRINTERS.
5. **Save → Apply**.

## 3. Verification

| Check | Command (client) | Expected |
|---|---|---|
| Lease obtained | `ipconfig /all` | IPv4 in the pool, *DHCP Enabled: Yes*, *DHCP Server* = 10.10.x.1 |
| Options correct | `ipconfig /all` | Gateway `.1`, DNS `.1`, *Connection-specific DNS suffix* `corp.techcorp.example` (STAFF only) |
| Renew works | `ipconfig /release` then `ipconfig /renew` | New lease within seconds |
| Server side | pfSense *Status → DHCP Leases* | Client listed with hostname `TC-LT-NNN` and MAC |
| Guest has no suffix | `ipconfig /all` on guest VM | No DNS suffix, DNS = 10.10.50.1 |

## 4. Troubleshooting – DORA

DHCP is four broadcasts/unicasts: **D**iscover → **O**ffer → **R**equest → **A**ck.

| Symptom | Where DORA breaks | Likely cause | Fix |
|---|---|---|---|
| 169.254.x.x (APIPA) | No Offer | Wrong VLAN on port, VLAN not on trunk, DHCP disabled on interface, pool full | Check port VLAN, `show interfaces trunk`, *Status → DHCP Leases* |
| Address from 192.168.x.x | Rogue Offer | Consumer router plugged in | DHCP snooping (see switch config), find port |
| IP OK, no internet by name | Options | Wrong DNS option | Check DNS servers in scope |
| Works wired, not on Wi-Fi | – | SSID mapped to wrong VLAN on AP | AP SSID → VLAN mapping |
| Pool exhausted | No Offer | Too many devices / lease too long | Shorten lease, check for rogue devices |

Packet capture to prove it: pfSense *Diagnostics → Packet Capture*,
interface STAFF, port 67/68 – you should see all four DORA packets.

## Design change NET-CHG-001

| Field | Value |
|---|---|
| Change | DHCP for VLAN 10/20 moved from the domain controllers (via DHCP relay) to TC-FW01 |
| Date | 2026-11-26 (Milestone 4) |
| Approved by | Operations Manager |

**Original design (Milestone 3):** TC-DC01/TC-DC02 serve VLAN 10/20 with DHCP
failover; the firewall relays requests; guests get DHCP from the firewall.

**Problem found while writing the build procedure:** pfSense does not allow its
**DHCP Relay** service while the **DHCP Server** is enabled on any interface
(stated in the Netgate pfSense DHCP Relay documentation – re-check on the
installed version). The guest VLAN must get DHCP from the firewall, so relay
and the guest server cannot coexist.

| Option | Verdict |
|---|---|
| A. Relay guest DHCP to the DCs as well | ❌ Guests would need a rule to reach the domain controllers – breaks BR-15 |
| B. Let the Wi-Fi APs serve guest DHCP | ❌ Depends on AP vendor features; splits DHCP over two systems |
| C. **Firewall serves DHCP for all VLANs** | ✅ Chosen |

**Consequences of C:**

- One place to manage DHCP; leases keep working when a DC is down for patching.
- DHCP failover between DCs is no longer needed (the firewall is already the
  single gateway – if it is down, nothing routes anyway).
- Domain-joined Windows clients still register their own A records in AD DNS
  (secure dynamic update), so name resolution of clients is unaffected.
- The Windows DHCP Server role is still practised as a lab exercise in Phase 2
  (`03-windows-server/dhcp/`) because it is common in job environments.

Files updated: `vlan-subnets.csv`, `ip-addressing-plan.md`,
`network-topology.md`, `hardware-inventory.csv` (DC roles), deployment checklist.
Lesson recorded in [lessons learned](../../15-documentation/lessons-learned/m4-network-infrastructure.md).
