# Master Deployment Checklist

| Field | Value |
|---|---|
| Document ID | DEP-PRC-002 |
| Owner | IT Specialist |
| Status | Approved – ticked off as the lab is built |
| Last reviewed | 2026-11-26 |

The single list that tells you whether the office is ready. Each item links to
the phase where it is built and evidenced. Items are ticked **only when done
in the lab with evidence** in `15-documentation/screenshots/`.

## 1. Planning & procurement (Milestone 3)

- [x] Business requirements approved – [business-requirements.md](../00-company-overview/business-requirements.md)
- [x] Floor plan, desk allocation and Wi-Fi placement – [office-floor-plan.md](planning/office-floor-plan.md)
- [x] Equipment list and budget within BR-30 / BR-31 – [equipment-list.md](equipment-inventory/equipment-list.md)
- [x] Asset tags and hostnames allocated – [hardware-inventory.csv](equipment-inventory/hardware-inventory.csv)
- [x] Software baseline and licence plan – [software-baseline.md](equipment-inventory/software-baseline.md)
- [x] Cabling, rack and switch-port plan – [cabling-plan.md](network-installation/cabling-plan.md)
- [x] Network topology and IP plan – [topology](../02-network-infrastructure/topology/network-topology.md), [IP plan](../02-network-infrastructure/ip-addressing/ip-addressing-plan.md)
- [x] Workstation standard and build checklist – [workstation-deployment](workstation-deployment/)
- [x] Deployment plan, cut-over and risks – [deployment-plan.md](planning/deployment-plan.md)

## 2. Network (Phase 1)

- [ ] Firewall installed, WAN1 + WAN2 failover tested
- [ ] VLANs 10/20/30/40/50/999 created; trunk to firewall working
- [ ] Inter-VLAN rules match the policy matrix; guest isolation tested
- [ ] Switch hardening: unused ports shut + VLAN 999, PortFast/BPDU guard on access ports
- [ ] Wi-Fi SSIDs `TechCorp` (VLAN 20) and `TechCorp-Guest` (VLAN 50) broadcasting
- [ ] Remote-access VPN tested from outside
- [ ] Every active drop verified on expected switch port

## 3. Servers & identity (Phases 2–3)

- [ ] TC-HV01 installed, RAID healthy, iDRAC on VLAN 10
- [ ] TC-DC01 and TC-DC02 promoted; replication healthy (`repadmin /replsummary`)
- [ ] DNS zones and forwarders; DHCP scopes with failover
- [ ] OU structure, groups (AGDLP), 20 user accounts from `employees.csv`
- [ ] Baseline GPOs linked and verified with `gpresult`
- [ ] TC-FS01 shares + NTFS permissions per department; DFS namespace
- [ ] TC-UPS01 shutdown signal tested on host and NAS

## 4. Microsoft 365 (Phases 5–6)

- [ ] `techcorp.example` verified; MX, SPF, DKIM, DMARC published
- [ ] Entra Connect syncing; UPNs match e-mail
- [ ] Licences assigned via group; shared mailboxes created
- [ ] Teams + SharePoint sites per department
- [ ] MFA / Conditional Access enforced; break-glass account excluded and monitored
- [ ] Intune compliance + BitLocker + update rings

## 5. Endpoints & printing (Phase 4)

- [ ] 22 laptops built against the build checklist
- [ ] 24 desks: dock + 2 monitors + keyboard/mouse tested
- [ ] TC-PRN01 printing and scan-to-e-mail; TC-PRN02 restricted to Finance
- [ ] Meeting rooms: Teams call test with screen share

## 6. Data protection (Phase 10)

- [ ] Nightly backup of VMs to TC-NAS01; offsite copy to cloud
- [ ] Microsoft 365 backup configured
- [ ] First restore test passed (file + full VM)

## 7. Go-live

- [ ] Mail and file migration complete and verified
- [ ] All 20 users signed in, MFA registered, AUP signed
- [ ] Helpdesk live: `support@` ticketing + Teams "IT Help" channel
- [ ] Deployment report written – `16-reports/deployment/`
