# Firewall Rule Base (Inter-VLAN Policy)

| Field | Value |
|---|---|
| Document ID | NET-REF-004 |
| Owner | IT Specialist |
| Status | Draft – baseline for Milestone 4; IPS, VPN and logging review follow in Phase 9 |
| Last reviewed | 2026-11-26 |
| Related requirements | BR-09, BR-15 |

Implements the policy matrix from the
[IP addressing plan](../ip-addressing/ip-addressing-plan.md#5-inter-vlan-policy-summary).
pfSense evaluates rules **on the interface where traffic enters**, top to
bottom, first match wins, and **blocks everything not explicitly passed**
(except the default LAN rules, which are removed).

## 1. Aliases (Firewall → Aliases)

| Alias | Type | Value |
|---|---|---|
| `NET_INTERNAL` | Network | 10.10.0.0/16 |
| `NET_RFC1918` | Network | 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 |
| `HOST_DCS` | Host | 10.10.30.11, 10.10.30.12 |
| `HOST_EXO_MX` | Host (FQDN) | techcorp-example.mail.protection.outlook.com |
| `HOST_FS` | Host | 10.10.30.20 |
| `NET_PRINTERS` | Network | 10.10.40.0/24 |
| `PORTS_AD` | Port | 53, 88, 123, 135, 389, 445, 464, 636, 3268, 3269, 9389, 49152:65535 |
| `PORTS_PRINT` | Port | 443, 631, 9100 |
| `PORTS_FW_ADMIN` | Port | 22, 80, 443 |

Aliases keep rules readable ("STAFF → HOST_DCS on PORTS_AD") and mean an IP
changes in one place only.

## 2. Rules per interface

### MGMT (VLAN 10)

| # | Action | Source | Destination | Port | Note |
|---|---|---|---|---|---|
| 1 | Pass | MGMT net | This firewall | PORTS_FW_ADMIN | Anti-lockout – admin GUI/SSH only from MGMT |
| 2 | Pass | MGMT net | any | any | Admin network; gateway *default* |

### STAFF (VLAN 20)

| # | Action | Source | Destination | Port | Note |
|---|---|---|---|---|---|
| 1 | Pass | STAFF net | STAFF address | 53 TCP/UDP, 123 UDP, ICMP echo | DNS + NTP on firewall (interim, until DCs exist); ping the gateway |
| 2 | **Block** | STAFF net | This firewall | PORTS_FW_ADMIN | Users must not reach the firewall GUI |
| 3 | Pass | STAFF net | HOST_DCS | PORTS_AD | Logon, Kerberos, LDAP, DNS, GPO (SMB) |
| 4 | Pass | STAFF net | HOST_FS | 445 TCP | File shares |
| 5 | Pass | STAFF net | NET_PRINTERS | PORTS_PRINT | Printing |
| 6 | **Block + log** | STAFF net | NET_INTERNAL | any | Everything else internal (MGMT, other servers, guests) |
| 7 | Pass | STAFF net | any | any | Internet – gateway `WAN_FAILOVER` |

### SERVERS (VLAN 30)

| # | Action | Source | Destination | Port | Note |
|---|---|---|---|---|---|
| 1 | Pass | SERVERS net | SERVERS address | 53, 123 | Firewall DNS forwarder / NTP |
| 2 | **Block** | SERVERS net | GUEST net | any | Servers never talk to guests |
| 3 | Pass | SERVERS net | NET_INTERNAL | any | Management of clients (WinRM, SNMP, UPS) – gateway default |
| 4 | Pass | SERVERS net | any | any | Updates, Entra Connect, offsite backup – gateway `WAN_FAILOVER` |

### PRINTERS (VLAN 40)

| # | Action | Source | Destination | Port | Note |
|---|---|---|---|---|---|
| 1 | Pass | PRINTERS net | PRINTERS address | 53, 123 | DNS, NTP |
| 2 | Pass | PRINTERS net | HOST_FS | 445 TCP | Scan-to-folder |
| 3 | Pass | PRINTERS net | HOST_EXO_MX | 25 TCP | Scan-to-e-mail via the Exchange Online inbound connector (M365-CHG-001 – was 587 SMTP AUTH to any) |
| 4 | **Block + log** | PRINTERS net | any | any | Printers start nothing else – firmware is untrusted |

### GUEST (VLAN 50)

| # | Action | Source | Destination | Port | Note |
|---|---|---|---|---|---|
| 1 | Pass | GUEST net | GUEST address | 53 TCP/UDP | DNS resolver on firewall |
| 2 | **Block** | GUEST net | This firewall | any | No GUI, no other services |
| 3 | **Block + log** | GUEST net | NET_RFC1918 | any | No internal or "other private" networks |
| 4 | Pass | GUEST net | any | any | Internet only – gateway `WAN_FAILOVER`, limiter 50/20 Mbit/s |

Client-to-client isolation inside VLAN 50 is enforced on the **APs**
(the firewall never sees traffic between two guests on the same SSID).

## 3. Verification matrix

Run [Test-TechCorpNetwork.ps1](../../07-powershell/network-diagnostics/Test-TechCorpNetwork.ps1)
from a client in each VLAN; it reads the expected result from the profile and
reports PASS/FAIL.

| Test | From STAFF | From GUEST | From PRINTERS* |
|---|:-:|:-:|:-:|
| 10.10.30.11:389 (LDAP) | ✅ | ❌ | ❌ |
| 10.10.30.20:445 (SMB) | ✅ | ❌ | ✅ |
| 10.10.10.2:22 (switch SSH) | ❌ | ❌ | ❌ |
| Firewall GUI :443 | ❌ | ❌ | ❌ |
| Internet 1.1.1.1:443 | ✅ | ✅ | ❌ |

\* printer behaviour tested by placing a test VM on the printer VLAN.

## 4. Change rules

Any rule change follows change management: description in the rule's
*Description* field with the ticket number, config backup
(*Diagnostics → Backup & Restore*) before and after, and a re-run of the
verification matrix.
