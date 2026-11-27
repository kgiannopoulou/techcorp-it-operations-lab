# 01 – Office Deployment

**Status:** ✅ Complete (Milestone 3) – design and plan; the build happens in the training phases.

Everything needed to take TechCorp from "empty office" to "20 people working":
someone else could order the equipment, cable the office and build a laptop
using only these documents.

| Folder / file | ID | Contents |
|---|---|---|
| [planning/deployment-plan.md](planning/deployment-plan.md) | DEP-REF-001 | Objective, scope, Gantt timeline, phase gates, cut-over weekend, risks, communications |
| [planning/office-floor-plan.md](planning/office-floor-plan.md) | DEP-REF-004 | Floor plan, rooms, desk allocation, Wi-Fi AP placement and channels |
| [equipment-inventory/equipment-list.md](equipment-inventory/equipment-list.md) | DEP-REF-002 | Capex €71,520 / opex €12,374, design decisions, risks |
| [equipment-inventory/hardware-inventory.csv](equipment-inventory/hardware-inventory.csv) | – | 114 assets with tags, hostnames, VLAN, IP, owner, lab equivalent |
| [equipment-inventory/software-baseline.md](equipment-inventory/software-baseline.md) | DEP-REF-003 | Core image, department software, licence plan |
| [network-installation/cabling-plan.md](network-installation/cabling-plan.md) | DEP-REF-005 | Cat6 standard, 44-drop schedule, rack elevation, switch port plan |
| [workstation-deployment/workstation-standard.md](workstation-deployment/workstation-standard.md) | DEP-STD-001 | Hardware tiers, desk standard, configuration baseline, lifecycle |
| [workstation-deployment/workstation-build-checklist.md](workstation-deployment/workstation-build-checklist.md) | DEP-PRC-001 | Per-laptop build checklist |
| [deployment-checklist.md](deployment-checklist.md) | DEP-PRC-002 | Master go-live checklist linking every phase |

The logical network design lives in [02-network-infrastructure](../02-network-infrastructure/)
(topology and IP plan), following the repository's organisational rule.
