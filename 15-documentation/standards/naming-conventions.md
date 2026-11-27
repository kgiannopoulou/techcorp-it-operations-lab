# Naming Conventions

| Field | Value |
|---|---|
| Document ID | DOC-STD-002 |
| Owner | IT Specialist |
| Status | Approved |
| Last reviewed | 2026-11-27 |

Consistent names make troubleshooting faster: from a hostname alone you should
know what the device is, and from a group name you should know what it grants.

## 1. Domains and identity

| Item | Value | Reason |
|---|---|---|
| Public / e-mail domain | `techcorp.example` | `.example` is reserved for documentation (RFC 2606) |
| AD DS forest / domain (FQDN) | `corp.techcorp.example` | A sub-domain of a domain we own avoids split-brain DNS and `.local` problems |
| NetBIOS name | `TECHCORP` | ≤ 15 characters |
| UPN suffix | `@techcorp.example` | Users sign in to AD and M365 with the same name as their e-mail |
| M365 initial domain | `techcorpsolutions.onmicrosoft.com` | Created with the tenant; never used by users |

## 2. User and admin accounts

| Account type | Format | Example |
|---|---|---|
| Standard user (`sAMAccountName`) | `firstname.lastname` (max 20 chars) | `historia.reiss` |
| Name collision | `firstname.m.lastname` (middle initial) | `mikasa.k.ackerman` |
| E-mail / UPN | `firstname.lastname@techcorp.example` | `historia.reiss@techcorp.example` |
| Privileged admin account – servers / DCs (Domain Admin) | `adm-firstname.lastname`, UPN `@corp.techcorp.example` | `adm-eren.yeager` |
| Privileged admin account – workstations / helpdesk (never Domain Admin) | `wadm-firstname.lastname`, UPN `@corp.techcorp.example` | `wadm-eren.yeager` |
| Service account | `svc-<application>` | `svc-backup` |
| Break-glass (cloud only, two) | `bg-adminNN@techcorpsolutions.onmicrosoft.com` | `bg-admin01`, `bg-admin02` |
| Cloud admin (cloud only, never synced) | `adm-firstname.lastname@techcorpsolutions.onmicrosoft.com` | `adm-eren.yeager@…onmicrosoft.com` |
| Room / resource mailbox | `room-<room>@techcorp.example` | `room-mr1@` |
| Device sender (no mailbox) | `<device>@techcorp.example` | `scanner@` |
| Shared mailbox | `<function>@techcorp.example` | `support@`, `accounts@`, `info@` |

Admins **never** use their privileged account for e-mail or browsing, and
`adm-` accounts never sign in to laptops (WIN-CHG-001,
[user-accounts.md](../../03-windows-server/users-and-groups/user-accounts.md#2-privileged-accounts--design-change-win-chg-001)).

## 3. Devices (hostname = asset tag)

Hostnames are ≤ 15 characters (NetBIOS limit) and upper-case.

| Device | Format | Examples |
|---|---|---|
| Laptop | `TC-LT-NNN` | `TC-LT-001` … `TC-LT-022` |
| Desktop (if ever needed) | `TC-DT-NNN` | `TC-DT-001` |
| Physical server / hypervisor | `TC-HV<NN>` | `TC-HV01` |
| Virtual server | `TC-<ROLE><NN>` | `TC-DC01`, `TC-DC02`, `TC-FS01` |
| Firewall | `TC-FW<NN>` | `TC-FW01` |
| Switch | `TC-SW<NN>` | `TC-SW01` |
| Wireless access point | `TC-AP<NN>` | `TC-AP01` |
| Printer / MFP | `TC-PRN<NN>` | `TC-PRN01` |
| NAS | `TC-NAS<NN>` | `TC-NAS01` |
| UPS | `TC-UPS<NN>` | `TC-UPS01` |

### Peripherals (asset tag only, no hostname)

| Peripheral | Format | Example |
|---|---|---|
| Monitor | `TC-MON-NNN` | `TC-MON-014` |
| Docking station | `TC-DCK-NNN` | `TC-DCK-014` |
| Headset | `TC-HS-NNN` | `TC-HS-003` |
| Meeting-room equipment | `TC-MR-NNN` | `TC-MR-001` |

## 4. Groups

| Scope | Format | Example | Used for |
|---|---|---|---|
| AD global (role) | `GG_<Department>_<Role>` | `GG_Finance_Users` | Who people are |
| AD domain local (resource) | `DL_<Type>_<Resource>[-<Subfolder>]_<RW\|RO\|List>` | `DL_FS_Finance_RW`, `DL_FS_Finance-Payroll_RW` | What they can access |
| M365 / Teams group | `grp-<department code, lower case>` (company-wide: `grp-all`) | `grp-sales` | Team + SharePoint site, dynamic membership |
| Licence group | `LIC_<SKU>` | `LIC_M365_BusinessPremium` | Group-based licensing |

`<Department>` is the short **department code** (WIN-CHG-003) – no spaces or
`&` in AD names:

| Department | Code (OU, groups, folder) |
|---|---|
| Management | `Management` |
| Finance | `Finance` |
| Human Resources | `HR` |
| Sales & Marketing | `Sales` |
| Software Development | `Development` |
| Customer Support | `Support` |
| IT | `IT` |

Source: [department-map.csv](../../03-windows-server/users-and-groups/department-map.csv).

Access rule (AGDLP): **A**ccounts → **G**lobal groups → **D**omain **L**ocal
groups → **P**ermissions. Users are never put directly on an ACL.

## 5. Group Policy Objects

`<C|U>-<Scope>-<Purpose>` – `C` = computer settings, `U` = user settings.

Examples: `C-Workstations-SecurityBaseline`, `C-Workstations-BitLocker`,
`U-AllUsers-DriveMappings`, `U-Finance-PrinterMapping`.

## 6. Network

| Item | Format | Example |
|---|---|---|
| VLAN name | `VLAN<ID>-<PURPOSE>` | `VLAN20-STAFF` |
| Wi-Fi SSID (staff) | `TechCorp` | 802.1X / WPA3-Enterprise later phase; WPA2/3-PSK initially |
| Wi-Fi SSID (guest) | `TechCorp-Guest` | Isolated, internet only |
| Wall drop | `D-NN` | `D-07` |
| Patch-panel port | `PP1-NN` | `PP1-07` (matches drop number) |
| Switch port | `Gi1/0/NN` / `port NN` | `Gi1/0/07` |

## 7. File shares

| Share | Path |
|---|---|
| Department data | `\\corp.techcorp.example\dfs\Departments\<Department>` |
| Company-wide | `\\corp.techcorp.example\dfs\Company` |
| Managers | `\\corp.techcorp.example\dfs\Managers` |
| IT (restricted) | `\\corp.techcorp.example\dfs\IT` (SMB share `IT$` on TC-FS01 – WIN-CHG-002) |

(Backed by `TC-FS01`; DFS namespace so the server can be replaced without
changing paths. Most personal files live in OneDrive, not on the file server.)
