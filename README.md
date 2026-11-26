# TechCorp IT Operations Lab

> A complete IT department simulation: I am the first and only IT Specialist at
> **TechCorp Solutions**, a fictional 20-employee company, and this repository is
> the IT operations manual I am building as I set up and run its environment.

[![Docs CI](https://github.com/kgiannopoulou/techcorp-it-operations-lab/actions/workflows/docs-ci.yml/badge.svg)](https://github.com/kgiannopoulou/techcorp-it-operations-lab/actions/workflows/docs-ci.yml)
![Status](https://img.shields.io/badge/status-Milestone%203%20complete-blue)
![License](https://img.shields.io/badge/license-MIT-green)

| 20 | 12 | 100+ | 1 |
|:--:|:--:|:--:|:--:|
| simulated employees | training phases | planned support scenarios | complete IT operations manual |

## Why this repository exists

The repository serves three purposes at the same time:

1. **Learning** – every phase is a hands-on lab: build it, break it, fix it, document it.
2. **Reference manual** – procedures are written so I can reuse them on the job
   when I meet the same problem again.
3. **Portfolio** – a recruiter or IT manager can see organised documentation,
   practical labs, scripts, diagrams and evidence of what I have learned.

## The company at a glance

| Item | Value |
|---|---|
| Company | TechCorp Solutions (fictional) – software development & IT consulting |
| Size | 20 employees in 6 departments + IT, one office, hybrid work |
| Office | ~260 m² open-plan floor, Athens, Greece (fictional address) |
| Identity | On-prem Active Directory `corp.techcorp.example` + Microsoft 365 / Entra ID (hybrid) |
| Network | Firewall, 48-port PoE+ managed switch, 3 Wi-Fi APs, 5 VLANs |
| Servers | 1 Hyper-V host running 2 domain controllers + 1 file server; NAS for backups |
| Endpoints | 20 Windows 11 Pro laptops with docks, 2 spares, 2 printers |

Full details: [00-company-overview](00-company-overview/).

## Repository map

| Folder | What lives there | Status |
|---|---|---|
| [00-company-overview](00-company-overview/) | Company profile, departments, employees, requirements, IT responsibilities | ✅ Milestone 2 |
| [01-office-deployment](01-office-deployment/) | Office plan, equipment inventory, cabling, workstation standard, deployment checklist | ✅ Milestone 3 |
| [02-network-infrastructure](02-network-infrastructure/) | Technical guides: topology, IP plan, VLANs, switching, routing, DHCP, DNS, firewall | 🟡 Design started |
| [03-windows-server](03-windows-server/) | Windows Server, Active Directory, GPO, file services, permissions | ⏳ Planned |
| [04-endpoint-management](04-endpoint-management/) | Windows 11, software, drivers, printers, peripherals | ⏳ Planned |
| [05-microsoft-365](05-microsoft-365/) | Entra ID, Exchange Online, Teams, SharePoint, OneDrive, Intune | ⏳ Planned |
| [06-helpdesk](06-helpdesk/) | Ticketing process and user-support procedures | ⏳ Planned |
| [07-powershell](07-powershell/) | Automation scripts for users, diagnostics and reporting | ⏳ Planned |
| [08-cybersecurity](08-cybersecurity/) | Endpoint protection, access control, phishing, incident response | ⏳ Planned |
| [09-backup-disaster-recovery](09-backup-disaster-recovery/) | Backup strategy, restore tests, recovery procedures | ⏳ Planned |
| [10-monitoring-maintenance](10-monitoring-maintenance/) | Network / server monitoring, health checks | ⏳ Planned |
| [11-it-asset-management](11-it-asset-management/) | Hardware inventory lifecycle, licences, warranties | ⏳ Planned |
| [12-policies-procedures](12-policies-procedures/) | Onboarding, offboarding, access management, AUP, change management | ⏳ Planned |
| [13-maintenance-calendar](13-maintenance-calendar/) | Daily / weekly / monthly / quarterly / yearly tasks | ⏳ Planned |
| [14-scenarios](14-scenarios/) | Practical support challenges, solved and written up | ⏳ Planned |
| [15-documentation](15-documentation/) | Standards, templates, diagrams, screenshots, glossary, lessons learned | ✅ Milestone 1 |
| [16-reports](16-reports/) | Deployment, incident and maintenance reports | ⏳ Planned |

### Organisational rule

To stop the repository turning into one big pile of notes, each kind of content
has exactly one home:

| Content | Home | Example |
|---|---|---|
| *How to configure* a technology | `02`–`05`, `07`–`10` | "Configure a DHCP scope with reservations" |
| *How to support a user* | `06-helpdesk` | "User cannot print – first-line checklist" |
| *A problem I was given and solved* | `14-scenarios` | "SC-NET-004: Finance VLAN has no internet" |
| *Evidence and diagrams* | `15-documentation` | Topology diagram, screenshots, lessons learned |

## Roadmap

The project is built in milestones. The foundation (Milestones 1–3) comes first;
after that each of the 12 training phases is delivered as its own milestone.
See [ROADMAP.md](ROADMAP.md) for the full plan and exit criteria.

| Milestone | Scope | Status |
|---|---|---|
| M1 | Repository foundation – structure, README, licence, documentation standards, templates, CI | ✅ Done |
| M2 | Company simulation – company, departments, employees, requirements, IT responsibilities | ✅ Done |
| M3 | Office deployment – inventory, equipment, topology, IP plan, workstation standard, deployment plan | ✅ Done |
| M4+ | Training phases 1–12 (networking lab → Windows Server → … → capstone) | ⏳ Next |

## How the lab is built

TechCorp is simulated, but the work is real. Every piece of production
equipment in the inventory has a **lab equivalent** (a Hyper-V / VirtualBox VM,
pfSense, a Microsoft 365 developer/trial tenant, Packet Tracer for switching),
so each procedure can be performed and evidenced on a single PC.
Screenshots and outputs are only added once a task has actually been carried
out in the lab – nothing in `15-documentation/screenshots/` is mocked up.

## Conventions used throughout

- Names, IPs, hostnames and asset tags follow
  [15-documentation/standards/naming-conventions.md](15-documentation/standards/naming-conventions.md).
- Every document follows
  [15-documentation/standards/documentation-standards.md](15-documentation/standards/documentation-standards.md)
  and starts from a template in [15-documentation/templates](15-documentation/templates/).
- The domain `techcorp.example` and all people in this repository are fictional
  (`.example` is reserved by RFC 2606 for documentation).
- No real credentials, licence keys or personal data are ever committed.

## License

[MIT](LICENSE)
