# Equipment Inventory

| File | Contents |
|---|---|
| [equipment-list.md](equipment-list.md) | What is bought and why, capex/opex budget, design decisions, risks |
| [hardware-inventory.csv](hardware-inventory.csv) | **Source of truth**: every asset (113 rows) with asset tag, hostname, spec, owner, location, VLAN, IP, warranty, lab equivalent |
| [software-baseline.md](software-baseline.md) | Core image, department software, Microsoft licence plan, disallowed software |

`hardware-inventory.csv` columns:
`AssetTag, Hostname, Category, Model, Specification, AssignedTo, Location, VLAN, IPAddress, WarrantyYears, Status, LabEquivalent`.
`Status` moves `Planned → Ordered → Received → Deployed → Retired` as the
deployment progresses. The CSV is validated in CI against the employee list
and IP plan. Ongoing lifecycle management moves to `11-it-asset-management` in Phase 11.
