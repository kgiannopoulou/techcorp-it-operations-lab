# Glossary

| Field | Value |
|---|---|
| Document ID | DOC-REF-001 |
| Owner | IT Specialist |
| Status | Living document – grows with every phase |
| Last reviewed | 2026-11-27 |

| Term | Meaning |
|---|---|
| **3-2-1 backup** | 3 copies of data, on 2 different media, 1 offsite |
| **ABE** | Access-based enumeration – a share only lists the folders and files the user can open |
| **AD DS** | Active Directory Domain Services – Microsoft's on-prem directory for users, computers and Group Policy |
| **AGDLP** | Accounts → Global groups → Domain Local groups → Permissions; the recommended way to grant access in AD |
| **AP** | Wireless Access Point |
| **Autopilot** | Windows service that configures a new laptop from the cloud when the user first signs in |
| **BitLocker** | Windows full-disk encryption, uses the TPM chip |
| **Break-glass account** | Emergency cloud admin account excluded from normal controls, used only if normal admin access fails |
| **Bypass traverse checking** | Windows user right (Everyone by default) that lets a user open a deep path without access to the folders above it |
| **CAL** | Client Access Licence – required for each user accessing Windows Server |
| **Capex / Opex** | Capital expenditure (one-off purchases) / operating expenditure (recurring costs) |
| **Conditional Access** | Entra ID policies that allow/block sign-in based on user, device, location and risk |
| **DC** | Domain Controller – server running AD DS |
| **DFS-N** | Distributed File System Namespace – a single path (`\corp.techcorp.example\dfs`) in front of one or more file servers |
| **DHCP failover** | Two DHCP servers sharing a scope so leases continue if one fails |
| **DHCP relay** | A router/firewall forwarding DHCP broadcasts from a VLAN to a DHCP server in another subnet |
| **Drop** | A network cable run from the patch panel to a wall/floor outlet |
| **DSRM** | Directory Services Restore Mode – offline recovery mode of a DC, with its own password set at promotion |
| **EDR** | Endpoint Detection and Response – behaviour-based endpoint security (e.g. Defender for Business) |
| **Entra Connect** | Tool that synchronises on-prem AD users to Entra ID (hybrid identity) |
| **Entra ID** | Microsoft's cloud identity service (formerly Azure AD) |
| **FSMO** | Flexible Single Master Operation – five AD roles (schema, naming, PDC, RID, infrastructure) held by one DC each |
| **FSRM** | File Server Resource Manager – quotas, file screens and storage reports on Windows file servers |
| **gMSA** | Group Managed Service Account – a service account whose long password AD rotates automatically |
| **GPO** | Group Policy Object – a set of settings applied to users/computers in AD |
| **GPP** | Group Policy Preferences – GPO items such as drive maps and local groups, with item-level targeting |
| **Hot-desking** | Any employee can use any free desk |
| **Hypercare** | Period of extra on-site support right after go-live |
| **iDRAC / iLO** | Out-of-band management controller in a server (Dell / HPE) |
| **Intune** | Microsoft's cloud device management (MDM) service |
| **Kerberos** | Default AD authentication protocol – ticket based, fails if clocks differ by more than 5 minutes |
| **LACP** | Link Aggregation Control Protocol – bundles several cables into one logical link |
| **LAPS** | Local Administrator Password Solution – unique, rotated local admin password per device |
| **MFA** | Multi-factor authentication |
| **MoSCoW** | Prioritisation: Must, Should, Could, Won't |
| **MS16-072** | 2016 security update after which user GPOs are read with the computer's credentials – filtered GPOs need Authenticated Users: Read |
| **NBD** | Next business day (warranty response) |
| **NTFS permissions** | File-system ACLs on folders and files – the real access control behind every TechCorp share |
| **OU** | Organisational Unit – a container in AD used to apply GPOs and delegate admin |
| **PDC emulator** | FSMO role holder that is the domain's time source and receives every password change and lockout first |
| **PoE+** | Power over Ethernet (802.3at, up to 30 W per port) |
| **Protected Users** | Built-in AD group that disables NTLM, credential caching and delegation for its members |
| **PSO** | Password Settings Object – a fine-grained password policy applied to specific groups |
| **RACI** | Responsible, Accountable, Consulted, Informed |
| **Recycle Bin (AD)** | Optional AD feature that restores deleted objects with all attributes and group memberships |
| **Router-on-a-stick** | One router/firewall interface carrying several VLANs as tagged sub-interfaces |
| **RPO / RTO** | Recovery Point Objective (max data loss) / Recovery Time Objective (max downtime) |
| **SET** | Switch Embedded Teaming – Hyper-V NIC teaming |
| **SLA** | Service Level Agreement – committed response/resolution times |
| **SRV record** | DNS record that tells clients which host offers a service, e.g. `_ldap._tcp.dc._msdcs` for domain controllers |
| **SSID** | Wi-Fi network name |
| **SYSVOL** | Folder replicated between DCs that holds GPO files and logon scripts |
| **TPM** | Trusted Platform Module – security chip used by BitLocker and Windows Hello |
| **Trunk** | A switch port carrying multiple VLANs with 802.1Q tags |
| **UPN** | User Principal Name – sign-in name in the form `user@domain` |
| **UPS** | Uninterruptible Power Supply |
| **USN rollback** | Replication failure caused by restoring an old copy (snapshot) of a domain controller |
| **VLAN** | Virtual LAN – logical separation of a switch into isolated networks |
| **VLSM** | Variable Length Subnet Masking – subnets of different sizes from one block |
