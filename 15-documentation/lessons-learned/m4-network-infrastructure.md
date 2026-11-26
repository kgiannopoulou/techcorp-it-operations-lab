# Lessons Learned: Milestone 4 – Network Infrastructure

| Field | Value |
|---|---|
| Document ID | DOC-LL-001 |
| Related phase / scenario | Phase 1 (M4), SC-NET-003 |
| Date | 2026-11-26 |

## What happened

Turned the Milestone 3 network design into build procedures, device
configurations, a lab environment, scripts and scenarios. Writing the
*procedures* (not just the design) exposed two design problems and one lab
constraint.

## What went well

- Keeping data in CSVs (VLANs, port plan, inventory) meant the switch config
  could be **generated** from the port plan, and CI catches mismatches.
- A consistent `10.10.<VLAN>.0/24` scheme made every procedure shorter.

## What went wrong / was harder than expected

| Problem | Found when | Change |
|---|---|---|
| pfSense DHCP Relay cannot run while the DHCP Server is enabled on any interface, so "DCs serve staff via relay, firewall serves guests" was impossible | Writing the DHCP procedure | **NET-CHG-001** – firewall serves DHCP for all VLANs |
| Meeting-room table ports were in the staff VLAN – a visitor with a cable would reach the file server | Designing scenario SC-NET-003 | **NET-CHG-002** – table ports moved to VLAN 50 |
| The lab PC runs Windows 11 Home – no Hyper-V | Planning the lab | Lab moved to **VirtualBox** (+ Packet Tracer for switch CLI) |

## What I learned (technical)

- A design isn't finished until you have written the click-by-click build –
  product limitations only show up at that level.
- IOS ACLs are stateless (replies need `established` / `echo-reply`),
  pfSense rules are stateful – the same policy needs different rule sets.
- `switchport trunk allowed vlan <list>` replaces the list; use `add`.
- Physical access to a port = network access to its VLAN; segmentation starts
  with port assignment.

## What I will do differently

| Action | Where it is documented | Done |
|---|---|---|
| Write the build procedure before marking any design "Approved" | documentation-standards.md §8 | ☑ |
| Review every port a visitor can physically reach | switch-configuration.md | ☑ |
| Execute the lab and replace "Designed" with "Solved" + evidence | 14-scenarios/scenario-index.md | ☐ |
