# IT Responsibilities

| Field | Value |
|---|---|
| Document ID | CO-REF-004 |
| Owner | IT Specialist |
| Status | Approved |
| Last reviewed | 2026-11-26 |

## 1. Role summary

**Job title:** IT Specialist (sole IT staff member)
**Reports to:** Sofia Dimitriou, Operations Manager
**Hours:** Mon–Fri 08:30–17:30, on-site

> Plan, deploy, secure, support and document all IT systems used by TechCorp's
> 20 employees, working with external vendors where specialist skills or
> warranty support are required.

## 2. Areas of responsibility

| # | Area | Key responsibilities | Repo folder |
|---|---|---|---|
| 1 | Networking | Firewall, switch, Wi-Fi, VLANs, DHCP/DNS, ISP liaison, VPN | `02` |
| 2 | Servers & identity | Hyper-V host, AD DS, DNS, DHCP, Group Policy, file services | `03` |
| 3 | Endpoints | Laptop build, software, drivers, printers, peripherals, meeting rooms | `04` |
| 4 | Microsoft 365 | Users, licences, Exchange Online, Teams, SharePoint, OneDrive, Intune | `05` |
| 5 | Helpdesk | Ticket handling, first- and second-line support, user training | `06`, `14` |
| 6 | Automation | PowerShell for repetitive tasks and reports | `07` |
| 7 | Security | MFA, endpoint protection, patching, access reviews, incident response | `08` |
| 8 | Backup & DR | Backup jobs, restore tests, recovery runbooks | `09` |
| 9 | Monitoring | Health checks, alerting, capacity | `10` |
| 10 | Asset management | Hardware/software inventory, licences, warranties, disposal | `11` |
| 11 | Policies | Onboarding, offboarding, access, acceptable use, change management | `12` |
| 12 | Documentation | Keep this manual current | `15` |

## 3. RACI

**R** = Responsible (does the work) · **A** = Accountable (approves/owns) ·
**C** = Consulted · **I** = Informed

| Activity | IT Specialist | Operations Manager | CEO | HR | Dept. managers | Vendor |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| IT budget & purchasing | R | A | C | – | C | – |
| Network & server changes | R/A | I | – | – | I | C |
| Major change (outage > 1 h, cost > €2 000) | R | A | I | – | I | C |
| New starter account & device | R | I | – | A | C | – |
| Leaver access removal | R | I | – | A | I | – |
| Access to department data | R | – | – | – | A | – |
| Security incident response | R | A | I | C | I | C |
| Backup & restore tests | R/A | I | – | – | – | – |
| Hardware failure under warranty | R | I | – | – | – | R |
| ISP outage | R | I | – | – | I | R |
| Policy approval (AUP, security) | R | C | A | C | I | – |

## 4. Service catalogue

| Service | Description | Request via |
|---|---|---|
| Account & access | New user, leaver, password reset, group/share access | HR request / ticket |
| Device | New/replacement laptop, docking, monitor, peripherals | Ticket |
| Software | Install / licence request from the approved list | Ticket + manager approval |
| E-mail & collaboration | Mailboxes, shared mailboxes, Teams, SharePoint sites | Ticket |
| Printing & scanning | Printer setup, scan-to-e-mail, toner | Ticket |
| Network | Wi-Fi, guest access, VPN | Ticket |
| Security | Suspicious e-mail, lost device, suspected compromise | **Phone / walk-up immediately** + ticket |
| Advice & training | How-to questions, new-starter IT induction | Ticket / Teams |

## 5. Support hours, priorities and SLAs

Requests go to **`support@techcorp.example`** (creates a ticket) or the
**IT Help** Teams channel. Security issues: walk up or phone extension 200.

| Priority | Definition | Example | First response | Target resolution |
|---|---|---|---|---|
| P1 – Critical | Company-wide outage or active security incident | Internet down, ransomware, e-mail down for everyone | 15 min | 4 h |
| P2 – High | One department or a key person cannot work | Finance share inaccessible, CEO laptop dead | 1 h | 1 business day |
| P3 – Normal | One user affected, workaround exists | Printer driver issue, Outlook slow | 4 business hours | 3 business days |
| P4 – Low | Request or question | New software, monitor arm | 1 business day | 5 business days / as scheduled |

Out of hours: no on-call. The CEO and Operations Manager have the IT
Specialist's mobile for **P1 only**, best effort.

## 6. Escalation contacts (vendors)

| Vendor / service | Used for | Contract |
|---|---|---|
| ISP (fibre) | Internet outage, line faults | Business SLA, 8 h fix |
| Mobile operator | 4G/5G failover SIM | Data plan |
| Laptop vendor | Hardware faults | 3-year next-business-day on-site |
| Server / NAS vendor | Hardware faults | 3-year NBD |
| Microsoft partner / CSP | Licensing, escalated M365 issues | Per incident |
| Cabling contractor | Structured cabling faults | 1-year workmanship warranty |
| Printer leasing company | MFP faults, toner | Managed print contract |

(Vendor names and phone numbers are kept in the password manager / internal
system, not in a public repository.)

## 7. Success measures (first year)

| KPI | Target |
|---|---|
| Tickets resolved within SLA | ≥ 90 % |
| User satisfaction (quarterly survey) | ≥ 4 / 5 |
| Devices compliant (encrypted, patched, AV healthy) | ≥ 95 % |
| Successful restore tests | 4 / 4 per year |
| Leavers disabled on last day | 100 % |
| Documented procedures for every recurring task | 100 % |
