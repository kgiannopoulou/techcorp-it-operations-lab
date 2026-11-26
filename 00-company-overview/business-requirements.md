# Business Requirements

| Field | Value |
|---|---|
| Document ID | CO-REF-003 |
| Owner | IT Specialist (approved by Operations Manager) |
| Status | Approved |
| Last reviewed | 2026-11-26 |

Every technical decision in this repository must trace back to a requirement
below. Requirement IDs (`BR-xx`) are referenced from procedures and designs.

Priority uses **MoSCoW**: **M**ust, **S**hould, **C**ould, **W**on't (this year).

## 1. Functional requirements

| ID | Requirement | Priority | How it will be met | Phase |
|---|---|---|---|---|
| BR-01 | Every employee has **one identity** used for Windows sign-in, e-mail and all Microsoft 365 apps | M | AD DS + Entra Connect sync, UPN = e-mail | 2, 5 |
| BR-02 | Company e-mail on `@techcorp.example` with shared mailboxes `support@`, `info@`, `accounts@` | M | Exchange Online | 5 |
| BR-03 | Each department has a **private file area**; a company-wide area is readable by all | M | SharePoint sites per department + `TC-FS01` DFS shares for legacy files, AGDLP groups | 3, 5 |
| BR-04 | Staff can work at **any desk** (hot-desking) with docking station + 2 monitors | M | USB-C docks, standard monitors at every desk | 3 (M3) |
| BR-05 | Reliable **Wi-Fi** throughout the office; separate **guest Wi-Fi** for visitors | M | 3 APs, SSIDs `TechCorp` / `TechCorp-Guest`, VLAN 50 isolated | 1 |
| BR-06 | Printing and **scan-to-e-mail** for all staff; Finance has a private printer | M | `TC-PRN01` MFP (open area), `TC-PRN02` (Finance office) | 4 |
| BR-07 | Teams meetings in both meeting rooms with screen and conference camera/mic | S | Meeting-room kits on VLAN 20 | 4 |
| BR-08 | Developers can run Docker/WSL2 and reach client environments over VPN | M | Developer tier laptops, client VPN profiles | 4 |
| BR-09 | Remote / hybrid staff can access all work resources from home securely | M | M365 cloud-first + firewall VPN for file server | 1, 5 |
| BR-10 | New starters are productive **on day 1**; leavers lose access **the same day** | M | Onboarding/offboarding procedures + PowerShell automation | 8, 12 |

## 2. Security requirements

| ID | Requirement | Priority | How it will be met | Phase |
|---|---|---|---|---|
| BR-11 | **MFA** for all users, all cloud sign-ins | M | Entra ID MFA / Conditional Access | 6 |
| BR-12 | All laptops **encrypted**; a lost laptop exposes no data | M | BitLocker with keys escrowed to AD/Entra | 4, 6 |
| BR-13 | Endpoint protection (AV/EDR) on every device, centrally reported | M | Microsoft Defender for Business | 9 |
| BR-14 | Users are **not local administrators**; admin rights are separate accounts | M | `adm-` accounts, LAPS, elevation process for developers | 3, 9 |
| BR-15 | Guests and IoT/printers **cannot reach** staff devices or servers | M | VLAN segmentation + firewall rules | 1 |
| BR-16 | Security updates installed within **14 days** (critical: 72 h) | M | WSUS/Windows Update for Business rings | 4, 6 |
| BR-17 | Staff receive phishing awareness training at onboarding and yearly | S | Phishing procedure + simulation | 9 |
| BR-18 | Admin and sign-in activity is logged and retained ≥ 90 days | S | Entra sign-in logs, Windows event forwarding | 9, 11 |

## 3. Availability and data protection

| ID | Requirement | Priority | Target | Phase |
|---|---|---|---|---|
| BR-19 | Business-hours availability of network, e-mail and file access | M | 99.5 % (≈ 1 h unplanned downtime / month) | all |
| BR-20 | **Backups** of servers and M365 data following 3-2-1 | M | Daily backup, 1 copy offsite/cloud | 10 |
| BR-21 | Recovery point objective (RPO) for file data | M | ≤ 24 h | 10 |
| BR-22 | Recovery time objective (RTO) – single file / full server | M | ≤ 4 h / ≤ 1 business day | 10 |
| BR-23 | Office survives a short **power cut** gracefully | M | UPS ≥ 15 min for rack, automatic server shutdown | M3, 11 |
| BR-24 | Restore tests performed and documented | M | Quarterly | 10, 13 |
| BR-25 | Internet outage does not stop Customer Support | S | 4G/5G failover on firewall | 1 |

## 4. Compliance

| ID | Requirement | Priority | Notes |
|---|---|---|---|
| BR-26 | GDPR: personal data (HR, Finance, client data) access restricted and auditable | M | Access reviews quarterly, data in EU region tenant |
| BR-27 | Software is properly **licensed** and licences are tracked | M | Licence register in `11-it-asset-management` |
| BR-28 | IT assets are inventoried with owner, location and warranty | M | [hardware-inventory.csv](../01-office-deployment/equipment-inventory/hardware-inventory.csv) |
| BR-29 | Acceptable Use Policy signed by every employee | M | `12-policies-procedures` |

## 5. Budget and constraints

| ID | Constraint |
|---|---|
| BR-30 | Initial deployment capex ≤ **€72 000** (hardware, cabling, installation). Estimate: [equipment-list.md](../01-office-deployment/equipment-inventory/equipment-list.md) |
| BR-31 | Recurring opex ≤ **€18 000 / year** (licences, ISP, backup storage, warranties) |
| BR-32 | One IT person: solutions must be **simple to operate** and well documented; prefer managed/cloud services where they remove routine work |
| BR-33 | Deployment complete before the office move on **15 Feb 2027**; no more than one working day of disruption |

## 6. Out of scope (Won't this year)

- On-prem Exchange, SharePoint Server or any on-prem application servers beyond AD/files.
- A second office or a secondary data centre.
- 24/7 support – IT support is business hours only, with a best-effort emergency contact.
- Full SIEM – logs are retained and reviewed, not correlated 24/7.
