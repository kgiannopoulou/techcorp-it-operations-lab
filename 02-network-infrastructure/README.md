# 02 – Network Infrastructure

**Status:** ✅ Milestone 4 – designed, configured and documented · 🧪 lab execution and evidence pending

Technical guides for building, configuring and troubleshooting TechCorp's network.
Start with the [lab environment](topology/lab-environment.md), then follow the build order.

| Area | Document | ID | Contents |
|---|---|---|---|
| Topology | [network-topology.md](topology/network-topology.md) | NET-REF-001 | Logical + physical topology, design rationale |
| Lab | [lab-environment.md](topology/lab-environment.md) | NET-PRC-006 | VirtualBox + pfSense build (`VBoxManage` script), build order, evidence list |
| IP addressing | [ip-addressing-plan.md](ip-addressing/ip-addressing-plan.md) · [vlan-subnets.csv](ip-addressing/vlan-subnets.csv) | NET-REF-002 | Subnets, static IPs, DHCP/DNS options, inter-VLAN policy matrix |
| Subnetting | [subnetting-guide.md](subnetting/subnetting-guide.md) | NET-REF-003 | Method, cheat sheet, VLSM exercise, 10 exercises with answers |
| VLANs | [vlan-configuration.md](vlans/vlan-configuration.md) | NET-PRC-001 | VLAN table, 802.1Q concepts, switch + pfSense config, verification |
| Switching | [switch-configuration.md](switching/switch-configuration.md) · [switch-port-plan.csv](switching/switch-port-plan.csv) · [tc-sw01.cfg](switching/tc-sw01.cfg) | NET-PRC-002 | 48-port plan, generated IOS-XE config, hardening rationale, rollback |
| Routing | [inter-vlan-routing.md](routing/inter-vlan-routing.md) | NET-PRC-003 | Router-on-a-stick, default route, dual-WAN failover, NAT |
| Firewall | [firewall-rules.md](firewall/firewall-rules.md) | NET-REF-004 | Aliases and per-VLAN rule base implementing the policy |
| DHCP | [dhcp-configuration.md](dhcp/dhcp-configuration.md) | NET-PRC-004 | Scopes, reservations, DORA troubleshooting, change NET-CHG-001 |
| DNS | [dns-design.md](dns/dns-design.md) | NET-PRC-005 | Namespaces, resolution path, resolver config, public records |
| Packet Tracer | [packet-tracer-lab/](packet-tracer-lab/) | NET-PRC-007 | Switch + router configs, 12 verification steps, break-fix list |
| Troubleshooting | [network-troubleshooting.md](troubleshooting/network-troubleshooting.md) | NET-REF-005 | Bottom-up method, decision tree, command cheat sheet |

Related: scripts in [07-powershell/network-diagnostics](../07-powershell/network-diagnostics/),
scenarios in [14-scenarios/networking](../14-scenarios/networking/),
lessons in [15-documentation/lessons-learned](../15-documentation/lessons-learned/m4-network-infrastructure.md).

## Design changes in Milestone 4

| ID | Change | Why |
|---|---|---|
| [NET-CHG-001](dhcp/dhcp-configuration.md#design-change-net-chg-001) | DHCP for all VLANs on the firewall (not the DCs) | pfSense DHCP Relay and DHCP Server cannot run at the same time |
| [NET-CHG-002](switching/switch-configuration.md#change-net-chg-002) | Meeting-room table ports moved to the guest VLAN | Visitors could have reached the staff VLAN |
