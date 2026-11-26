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

## Training phases (Milestone 4 onwards)

Each phase = one milestone = one or more lab sessions, a set of procedures, at
least five solved scenarios, and evidence.

| Phase | Milestone | Topic | Main folders |
|---|---|---|---|
| 1 | M4 | Network infrastructure: IP addressing, VLANs, DHCP, DNS, switching, routing (pfSense + Packet Tracer) | `02`, `07`, `14` |
| 2 | M5 | Windows Server install, AD DS, DNS, DHCP, second DC | `03` |
| 3 | M6 | Users, groups, OU design, Group Policy, file shares & NTFS permissions | `03` |
| 4 | M7 | Windows 11 deployment, domain join, software, drivers, printers | `04` |
| 5 | M8 | Microsoft 365: Entra Connect, licences, Exchange Online, Teams, SharePoint, OneDrive | `05` |
| 6 | M9 | Intune / device compliance, MFA, Conditional Access | `05`, `08` |
| 7 | M10 | Helpdesk: ticketing process, SLAs, first-line procedures | `06`, `14` |
| 8 | M11 | PowerShell automation: onboarding, diagnostics, reports | `07` |
| 9 | M12 | Cybersecurity: Defender, hardening, phishing, incident response, logs | `08` |
| 10 | M13 | Backup & disaster recovery: 3-2-1, restore tests, DR runbooks | `09` |
| 11 | M14 | Monitoring, maintenance & asset management | `10`, `11`, `13` |
| 12 | M15 | Policies, procedures & capstone "first year at TechCorp" scenario week | `12`, `14`, `16` |
