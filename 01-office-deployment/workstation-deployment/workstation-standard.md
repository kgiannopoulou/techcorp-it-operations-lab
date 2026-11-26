# Workstation Standard

| Field | Value |
|---|---|
| Document ID | DEP-STD-001 |
| Owner | IT Specialist |
| Status | Approved |
| Last reviewed | 2026-11-26 |
| Related requirements | BR-01, BR-04, BR-08, BR-12, BR-13, BR-14, BR-16 |

Every TechCorp laptop is built to this standard so that any laptop works at any
desk and a failed laptop can be replaced from spares in under an hour.

## 1. Hardware tiers

| Tier | Users | CPU | RAM | Storage | Screen | Qty |
|---|---|---|---|---|---|---:|
| Standard | Management, Finance, HR, Sales, Support | Intel Core Ultra 5 (or AMD equivalent) | 16 GB | 512 GB NVMe | 14″ FHD+ | 13 + 2 spares |
| Developer | Software Development | Core Ultra 7 | 32 GB | 1 TB NVMe | 14″ | 5 |
| Creative | Marketing Specialist | Core Ultra 7 + 8 GB dGPU | 32 GB | 1 TB NVMe | 16″ 100 % sRGB | 1 |
| IT | IT Specialist | Core Ultra 7 | 32 GB | 1 TB NVMe | 14″ | 1 |

### Mandatory for every tier

- TPM 2.0, UEFI Secure Boot, firmware supports Windows 11 and BitLocker.
- USB-C with Power Delivery and DisplayPort Alt-Mode (works with the standard dock).
- Wi-Fi 6/6E, Bluetooth 5, 1080p webcam with privacy shutter, fingerprint or IR camera (Windows Hello).
- 3-year next-business-day on-site warranty.
- One model per tier for the whole fleet → one driver pack per tier.

## 2. Desk standard (identical at all 24 desks)

| Item | Spec |
|---|---|
| Docking station | USB-C/Thunderbolt, 100 W, 2× DisplayPort, Gigabit Ethernet to wall drop |
| Monitors | 2 × 24″ 1080p, height-adjustable, connected to dock |
| Keyboard + mouse | Wired USB, connected to dock |
| Power | Laptop charges from dock; no laptop chargers left on desks |

## 3. Software and configuration baseline

| Setting | Standard | Enforced by (target phase) |
|---|---|---|
| OS | Windows 11 Pro, latest supported feature release, en-US UI + Greek keyboard | Image / Autopilot (4) |
| Hostname | `TC-LT-NNN` = asset tag | Build (4) |
| Domain | Hybrid joined: `corp.techcorp.example` + Entra ID | Build (2, 5) |
| Local admin | Built-in admin disabled; Windows LAPS manages a local recovery account | GPO / Intune (3, 6) |
| User rights | Standard user; developers request elevation | GPO (3) |
| Encryption | BitLocker XTS-AES 256, TPM-only, recovery key escrowed to AD + Entra ID | GPO / Intune (4, 6) |
| Antivirus / EDR | Microsoft Defender for Business, tamper protection on | Intune (9) |
| Updates | Windows Update for Business: pilot ring (IT + 2 users) → broad ring after 7 days | Intune (6) |
| Firewall | Windows Defender Firewall on, all profiles | GPO (3) |
| Screen lock | 10 minutes idle, password on resume | GPO (3) |
| OneDrive | Known Folder Move – Desktop, Documents, Pictures | GPO (5) |
| Power | Sleep on battery 15 min; on dock never sleep while on AC | GPO (3) |
| Software | Core image + department add-ons from [software-baseline.md](../equipment-inventory/software-baseline.md) | Intune / winget (4) |

## 4. Lifecycle

| Stage | Rule |
|---|---|
| Purchase | Only standard tier models |
| Deploy | Built with [workstation-build-checklist.md](workstation-build-checklist.md), recorded in inventory |
| Refresh | Every 4 years, or earlier if repair cost > 50 % of replacement |
| Repair | Under warranty → vendor; out of warranty → evaluate |
| Retire | Data wiped (BitLocker key destroyed + reset), asset status `Retired`, WEEE disposal certificate |
