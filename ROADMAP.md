# Roadmap

The repository is built milestone by milestone. A milestone is only closed when
its **exit criteria** are met – nothing is skipped because a later topic looks
more interesting.

## Foundation milestones

### ✅ Milestone 1 – Repository foundation

- [x] GitHub repository, licence, `.gitignore`
- [x] Top-level folder structure (00–16), each folder with a README stating its purpose and status
- [x] Root README with repository map and organisational rule
- [x] Documentation standards and naming conventions
- [x] Templates: procedure, scenario, ticket, lessons learned, report
- [x] Issue templates for new scenarios and documentation tasks
- [x] CI: Markdown lint + internal link check + data validation

**Exit criteria:** a new document can be created from a template, follows one
standard, and CI fails if it is malformed or links to a missing file.

### ✅ Milestone 2 – Company simulation

- [x] Company profile, mission, working model
- [x] Departments, headcount and department needs
- [x] Employee directory (20 fictional employees) as Markdown + CSV source data
- [x] Business requirements (functional, security, availability, budget, compliance)
- [x] IT responsibilities, RACI, service catalogue, support hours and SLAs

**Exit criteria:** every later technical decision can be traced back to a
business requirement (`BR-xx`).

### ✅ Milestone 3 – Office deployment

- [x] Office floor plan, room list and network drop plan
- [x] Deployment plan with phases, timeline, risks and rollback points
- [x] Equipment list with budget (production item + lab equivalent)
- [x] Hardware inventory (CSV) with asset tags, hostnames and assignments
- [x] Software baseline and licence plan
- [x] Cabling / rack / patch-panel plan
- [x] Logical network topology and IP addressing plan (VLANs, subnets, reserved ranges)
- [x] Workstation standard and build checklist
- [x] Master deployment checklist

**Exit criteria:** someone else could order the equipment, cable the office and
build a workstation using only this repository.

### 🟡 Milestone 4 – Network infrastructure (Training Phase 1) – documentation complete, lab evidence pending

- [x] Subnetting guide, VLSM exercise and subnet calculator script with self-tests in CI
- [x] VLAN design and configuration (switch + firewall)
- [x] Switch port plan (CSV, CI-validated) and full generated TC-SW01 configuration with hardening
- [x] Inter-VLAN routing, default route, dual-WAN failover and NAT
- [x] Firewall rule base implementing the inter-VLAN policy
- [x] DHCP scopes and DNS design (resolver now, AD DNS from Phase 2)
- [x] Lab environment for Windows 11 Home: VirtualBox + pfSense + Packet Tracer configs
- [x] Network troubleshooting method; `Test-TechCorpNetwork.ps1` policy checker
- [x] 5 networking scenarios designed; lessons learned; design changes NET-CHG-001/002
- [ ] Lab executed end-to-end with screenshots / CSV evidence; scenarios moved from *Designed* to *Solved*

**Exit criteria:** every network procedure can be followed step by step, and the
policy can be verified automatically from any VLAN. *Remaining:* lab execution
and evidence (needs VirtualBox and Packet Tracer installed on the lab PC).

### 🟡 Milestone 5 – Windows Server and Active Directory (Training Phases 2–3) – documentation complete, lab evidence pending

- [x] Server builds for TC-DC01 / TC-DC02 / TC-FS01 in VirtualBox (Server Core where possible)
- [x] Forest `corp.techcorp.example`, second DC, site and subnets, PDC time source, Recycle Bin, FSMO plan
- [x] AD-integrated DNS, forwarder to the firewall, scavenging, client switch-over (DHCP option 6)
- [x] OU design (23 OUs) and delegation (helpdesk reset/unlock, workstation join)
- [x] 28 AGDLP groups, 20 users from `employees.csv`, tiered admin accounts (`adm-` / `wadm-`), password policy + PSO
- [x] 13 GPOs designed; registry-based settings as data; manual settings click-by-click; drive maps with item-level targeting
- [x] File server: folders, NTFS (no Deny, protected department roots), shares with ABE, DFS namespace, quotas, file screen, shadow copies
- [x] Offline AD plan + self-test in CI (naming, AGDLP, GPO targets, 65 effective-access tests); deploy and verify scripts
- [x] 8 scenarios designed (Windows, accounts, infrastructure); lessons learned; design changes WIN-CHG-001/002/003
- [ ] Lab executed end-to-end (`Test-TechCorpAd.ps1` all PASS) with screenshots / CSV evidence; scenarios moved to *Solved*

**Exit criteria:** the whole domain can be rebuilt from the CSVs and scripts,
and every expected access decision is tested automatically. *Remaining:* lab
execution and evidence.

### 🟡 Milestone 6 – Workstations and Microsoft 365 (Training Phases 4–5) – documentation complete, lab evidence pending

- [x] Deployment strategy (clean install + domain join + hybrid Entra join; Autopilot later) and step-by-step laptop build incl. VirtualBox vTPM/Secure Boot lab VM
- [x] BitLocker with recovery keys escrowed to AD and Entra ID; drivers/firmware with BitLocker suspension
- [x] App catalogue (22 apps, by department and tier) + Office Deployment Tool config; `Install-TechCorpBaseline.ps1` with CI self-test; `Test-TechCorpEndpoint.ps1`
- [x] Print server on TC-FS01, GPP printers, Point-and-Print hardening (END-CHG-001); desks, headsets, Teams Rooms
- [x] Tenant, two break-glass accounts, least-privilege cloud admin, security defaults until M7
- [x] Entra Connect Sync on TC-SYNC01: PHS, OU filtering from `ou-structure.csv`, hybrid join (M365-CHG-002: Disabled OU synced)
- [x] Group-based licensing (no nesting, usage location), joiner/mover/leaver cloud steps
- [x] Exchange Online: 4 shared + 2 room mailboxes, DKIM/DMARC, preset security, scan-to-e-mail connector (M365-CHG-001), Gmail migration
- [x] 7 Teams on dynamic groups, tenant policies; SharePoint sharing levels per site, intranet, OneDrive KFM GPO + sync restriction
- [x] Offline M365 plan + self-test in CI; deploy and verify scripts; 8 scenarios designed; lessons learned
- [ ] Lab tenant and lab laptop built; `Test-TechCorpEndpoint` and `Test-TechCorpM365` all PASS with evidence; scenarios moved to *Solved*

**Exit criteria:** a new starter can be given a working laptop, mailbox,
teams and files on day 1 from `employees.csv` and the scripts, and the
tenant's security-relevant settings are tested automatically. *Remaining:*
lab execution and evidence.

### ⏳ Milestone 7 – Intune, MFA and Conditional Access (Training Phase 6) – not started

Done out of order: M8 was requested first. M7 is next.

### 🟡 Milestone 8 – PowerShell administration (Training Phase 7) – scripts and tests complete, lab runs pending

- [x] Shared module `TechCorp.Admin` (21 functions, pure where possible, `-Now` injectable) used by every new script
- [x] Joiner script: validation, unique logon names, employee ID, spare laptop, OU/groups from the CSVs, disabled-until-start account, one-time password shown once (PS-CHG-001)
- [x] Leaver script: safety checks, rollback record, cloud steps, disable/reset/strip groups/move, in the order that keeps the mailbox
- [x] Reports: stale accounts (users + computers), password expiry reminders for `adm-`/`wadm-` (PS-CHG-002), hardware inventory with warranty and live CIM collection
- [x] Maintenance: server health (uptime, disks, reboot, role services, event log, clock), retention clean-up with safety rails, service-port test from `data/server-roles.csv`, daily check → one HTML page and exit code
- [x] 248 Pester tests (unit + script tests with AD/Graph/EXO mocks + script standards), run in CI on Linux (PS 7) and Windows (PS 5.1 + 7)
- [x] 5 scenarios designed (SC-PS-001 … 005); lessons learned; design changes PS-CHG-001/002
- [ ] Scripts run against the lab domain and tenant, evidence in `16-reports/`; scenarios moved to *Solved*

**Exit criteria:** joiners, leavers and the recurring reviews are one command
each, every rule they apply is covered by an automated test, and nothing
changes without `-WhatIf` support and a record. *Remaining:* lab runs against
a live domain (needs the M5 lab).

## Training phases (Milestone 4 onwards)

Each phase = one milestone (except Phases 2–3 → M5 and Phases 4–5 → M6) = one or more lab sessions, a set of procedures, at
least five solved scenarios, and evidence.

| Phase | Milestone | Topic | Main folders |
|---|---|---|---|
| 1 | M4 | Network infrastructure: IP addressing, VLANs, DHCP, DNS, switching, routing (pfSense + Packet Tracer) | `02`, `07`, `14` |
| 2 | M5 | Windows Server install, AD DS, DNS, second DC | `03` |
| 3 | M5 | Users, groups, OU design, Group Policy, file shares & NTFS permissions | `03`, `07`, `14` |
| 4 | M6 | Windows 11 deployment, domain join, software, drivers, printers | `04`, `07`, `14` |
| 5 | M6 | Microsoft 365: Entra Connect, licences, Exchange Online, Teams, SharePoint, OneDrive | `05` |
| 6 | M7 | Intune / device compliance, MFA, Conditional Access | `05`, `08` |
| 7 | M8 | PowerShell administration: onboarding/offboarding, reports, health checks, Pester tests | `07`, `14` |
| 8 | M9 | Helpdesk: ticketing process, SLAs, first-line procedures | `06`, `14` |
| 9 | M10 | Cybersecurity: Defender, hardening, phishing, incident response, logs | `08` |
| 10 | M11 | Backup & disaster recovery: 3-2-1, restore tests, DR runbooks | `09` |
| 11 | M12 | Monitoring, maintenance & asset management | `10`, `11`, `13` |
| 12 | M13 | Policies, procedures & capstone "first year at TechCorp" scenario week | `12`, `14`, `16` |
