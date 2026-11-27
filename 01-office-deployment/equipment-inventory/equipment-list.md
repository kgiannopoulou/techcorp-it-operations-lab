# Equipment List and Budget

| Field | Value |
|---|---|
| Document ID | DEP-REF-002 |
| Owner | IT Specialist |
| Status | Approved for purchase |
| Last reviewed | 2026-11-26 |
| Related requirements | BR-04, BR-05, BR-06, BR-07, BR-12, BR-19, BR-20, BR-23, BR-30, BR-31 |

Every asset is listed individually in
[hardware-inventory.csv](hardware-inventory.csv) (114 rows). This document
explains **what** is bought, **why**, and **what it costs**. Prices are
realistic 2026–27 EU business list-price estimates excluding VAT – they are
for planning practice, not quotes.

## 1. Capital expenditure (one-off)

| Category | Item | Qty | Unit (€) | Total (€) |
|---|---|---:|---:|---:|
| Network | Firewall appliance (TC-FW01) + 4G/5G USB modem for failover | 1 | 900 | 900 |
| Network | 48-port PoE+ managed switch (TC-SW01) | 1 | 1,500 | 1,500 |
| Network | Wi-Fi 6 ceiling access points (TC-AP01–03) | 3 | 250 | 750 |
| Network | Structured cabling: Cat6 drops installed and certified | 44 | 90 | 3,960 |
| Network | 18U 800 mm floor rack, 2× 24-port Cat6 patch panels, cable management, PDU | 1 | 1,100 | 1,100 |
| Server | 1U rack server (TC-HV01), 3-year NBD warranty | 1 | 7,500 | 7,500 |
| Server | Windows Server 2025 Standard, 16-core licence (2 licences = 4 VMs) | 2 | 1,100 | 2,200 |
| Server | Windows Server 2025 User CALs | 20 | 45 | 900 |
| Server | 4-bay rack NAS (TC-NAS01) + 4× 8 TB NAS disks | 1 | 1,800 | 1,800 |
| Server | 1500 VA rack UPS with network card (TC-UPS01) | 1 | 900 | 900 |
| Endpoints | Standard laptop (13 users + 2 spares) | 15 | 1,100 | 16,500 |
| Endpoints | Developer / IT laptop (32 GB RAM) | 6 | 1,600 | 9,600 |
| Endpoints | Creative laptop (Marketing) | 1 | 2,200 | 2,200 |
| Endpoints | USB-C docking station (one per desk) | 24 | 180 | 4,320 |
| Endpoints | 24″ monitor (two per desk) | 48 | 150 | 7,200 |
| Endpoints | Keyboard + mouse set (one per desk) | 24 | 40 | 960 |
| Endpoints | Teams-certified headset (Support + 2 spares) | 4 | 120 | 480 |
| Endpoints | Meeting-room kit: video bar + 55″ display + mount | 2 | 2,500 | 5,000 |
| Printing | A4 mono laser printer – Finance (TC-PRN02) | 1 | 350 | 350 |
| Reserve | Contingency (≈ 5 %) | 1 | 3,400 | 3,400 |
| **Total** | | | | **71,520** |

### Breakdown

| Category | Total (€) | Share |
|---|---:|---:|
| Endpoints | 46,260 | 65 % |
| Server & storage | 13,300 | 19 % |
| Network & cabling | 8,210 | 11 % |
| Printing | 350 | < 1 % |
| Contingency | 3,400 | 5 % |
| **Total** | **71,520** | **within BR-30 (€72,000)** |

The open-plan MFP (`TC-PRN01`) is **leased** under a managed-print contract
(toner and repairs included), so it appears under opex instead.

## 2. Operating expenditure (yearly)

| Item | Basis | € / year |
|---|---|---:|
| Microsoft 365 Business Premium | 20 users × ~€20.60 × 12 | 4,944 |
| Business fibre internet (1 Gbps, static IP) | €100 / month | 1,200 |
| 4G/5G failover data SIM | €20 / month | 240 |
| Firewall support & security subscription | yearly | 400 |
| Offsite backup storage (cloud object storage, ~4 TB) | usage | 350 |
| Microsoft 365 backup (third-party SaaS) | 20 users × ~€2 × 12 | 480 |
| Managed-print lease – TC-PRN01 | €150 / month | 1,800 |
| Adobe Creative Cloud (1 user) | yearly | 900 |
| Business password manager | 20 users × ~€4 × 12 | 960 |
| Domain, DNS, public TLS certificate | yearly | 100 |
| Spares & consumables (cables, adapters, batteries) | reserve | 1,000 |
| **Total** | | **12,374** – within BR-31 (€18,000) |

## 3. Key design decisions

| Decision | Choice | Why | Alternative rejected |
|---|---|---|---|
| Laptops vs desktops | **Laptops for everyone** + docks | 12 of 20 staff are hybrid; hot-desking (BR-04) | Desktops + separate laptops – double the devices to manage |
| Laptop tiers | Standard / Developer / Creative / IT | Pay for performance only where the work needs it | One high-spec model for all – ~€8k more |
| OS edition | **Windows 11 Pro** (upgraded to Enterprise E3 rights via M365 Business Premium) | Domain join, BitLocker, Group Policy, Intune | Windows 11 Home – cannot join a domain |
| Monitors | 2 × 24″ per desk | Productivity; identical at every desk for hot-desking | Single wide monitor – mixed opinions, pricier |
| Switch size | **48 ports** | 44 drops + rack devices + growth (see [cabling plan](../network-installation/cabling-plan.md)) | 24 ports – already full on day one |
| Server | **One** Hyper-V host with 3 VMs | 20 users do not justify a cluster; VMs make restore/migration easy | Two hosts – €7.5k for a risk mitigated by backups + cloud-first |
| Domain controllers | **Two** DC VMs | AD/DNS survive patching or corruption of one DC | One DC – single point of failure for logons and DNS |
| Backup target | Rack NAS + cloud copy | 3-2-1 rule (BR-20) | USB drives – manual, unreliable |
| UPS | 1500 VA line-interactive, network card | ~20 min runtime for rack load, graceful shutdown (BR-23) | No UPS – unacceptable for servers |
| Printing | Leased MFP + small owned printer | Lease covers toner/repairs; Finance confidentiality (BR-06) | Several small printers – more drivers and consumables |

## 4. Known risks

| Risk | Impact | Mitigation |
|---|---|---|
| Single Hyper-V host fails | Logons via cached credentials only; file server down | NBD warranty, nightly VM backups to NAS, most data in M365 (cloud) |
| Both DCs on the same host | Host failure takes both DCs | Accepted risk for this size; Entra ID cloud sign-in keeps M365 working; revisit in year 2 |
| Single ISP | Internet outage stops cloud work | 4G/5G failover (BR-25) |
| Laptop supply delays | Deployment slip | Order in week 1; 2 spares; existing devices used temporarily |
