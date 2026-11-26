# Glossary

| Field | Value |
|---|---|
| Document ID | DOC-REF-001 |
| Owner | IT Specialist |
| Status | Living document – grows with every phase |
| Last reviewed | 2026-11-26 |

| Term | Meaning |
|---|---|
| **3-2-1 backup** | 3 copies of data, on 2 different media, 1 offsite |
| **AD DS** | Active Directory Domain Services – Microsoft's on-prem directory for users, computers and Group Policy |
| **AGDLP** | Accounts → Global groups → Domain Local groups → Permissions; the recommended way to grant access in AD |
| **AP** | Wireless Access Point |
| **Autopilot** | Windows service that configures a new laptop from the cloud when the user first signs in |
| **BitLocker** | Windows full-disk encryption, uses the TPM chip |
| **Break-glass account** | Emergency cloud admin account excluded from normal controls, used only if normal admin access fails |
| **CAL** | Client Access Licence – required for each user accessing Windows Server |
| **Capex / Opex** | Capital expenditure (one-off purchases) / operating expenditure (recurring costs) |
| **Conditional Access** | Entra ID policies that allow/block sign-in based on user, device, location and risk |
| **DC** | Domain Controller – server running AD DS |
| **DFS-N** | Distributed File System Namespace – a single path (`\corp.techcorp.example\dfs`) in front of one or more file servers |
| **DHCP failover** | Two DHCP servers sharing a scope so leases continue if one fails |
| **DHCP relay** | A router/firewall forwarding DHCP broadcasts from a VLAN to a DHCP server in another subnet |
| **Drop** | A network cable run from the patch panel to a wall/floor outlet |
| **EDR** | Endpoint Detection and Response – behaviour-based endpoint security (e.g. Defender for Business) |
| **Entra ID** | Microsoft's cloud identity service (formerly Azure AD) |
| **Entra Connect** | Tool that synchronises on-prem AD users to Entra ID (hybrid identity) |
| **GPO** | Group Policy Object – a set of settings applied to users/computers in AD |
| **Hot-desking** | Any employee can use any free desk |
| **Hypercare** | Period of extra on-site support right after go-live |
| **iDRAC / iLO** | Out-of-band management controller in a server (Dell / HPE) |
| **Intune** | Microsoft's cloud device management (MDM) service |
| **LACP** | Link Aggregation Control Protocol – bundles several cables into one logical link |
| **LAPS** | Local Administrator Password Solution – unique, rotated local admin password per device |
| **MFA** | Multi-factor authentication |
| **MoSCoW** | Prioritisation: Must, Should, Could, Won't |
| **NBD** | Next business day (warranty response) |
| **OU** | Organisational Unit – a container in AD used to apply GPOs and delegate admin |
| **PoE+** | Power over Ethernet (802.3at, up to 30 W per port) |
| **RACI** | Responsible, Accountable, Consulted, Informed |
| **Router-on-a-stick** | One router/firewall interface carrying several VLANs as tagged sub-interfaces |
| **RPO / RTO** | Recovery Point Objective (max data loss) / Recovery Time Objective (max downtime) |
| **SET** | Switch Embedded Teaming – Hyper-V NIC teaming |
| **SLA** | Service Level Agreement – committed response/resolution times |
| **SSID** | Wi-Fi network name |
| **TPM** | Trusted Platform Module – security chip used by BitLocker and Windows Hello |
| **Trunk** | A switch port carrying multiple VLANs with 802.1Q tags |
| **UPN** | User Principal Name – sign-in name in the form `user@domain` |
| **UPS** | Uninterruptible Power Supply |
| **VLAN** | Virtual LAN – logical separation of a switch into isolated networks |
| **VLSM** | Variable Length Subnet Masking – subnets of different sizes from one block |
