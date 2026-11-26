# Software Baseline and Licence Plan

| Field | Value |
|---|---|
| Document ID | DEP-REF-003 |
| Owner | IT Specialist |
| Status | Approved |
| Last reviewed | 2026-11-26 |
| Related requirements | BR-01, BR-02, BR-08, BR-13, BR-27 |

Only software on this list is installed on company devices. Anything else
goes through a software request ticket (manager approval + licence check).

## 1. Core image – every laptop

| Software | Purpose | Licence | Deployed by (target) |
|---|---|---|---|
| Windows 11 Pro 24H2+ (Enterprise E3 rights via M365 BP) | Operating system | OEM + M365 Business Premium | Factory / Autopilot |
| Microsoft 365 Apps for business | Word, Excel, PowerPoint, Outlook, OneNote | M365 Business Premium | Intune / ODT |
| Microsoft Teams | Chat, meetings, calling | M365 Business Premium | Bundled |
| OneDrive (Known Folder Move) | Desktop/Documents/Pictures sync | M365 Business Premium | GPO / Intune |
| Microsoft Edge | Default browser, managed | Free | Built-in, policies via GPO |
| Microsoft Defender for Business | AV / EDR | M365 Business Premium | Intune onboarding |
| Adobe Acrobat Reader | PDF viewing | Free | Intune / winget |
| 7-Zip | Archives | Free (LGPL) | winget |
| Password manager desktop app + browser extension | Credential storage | Business subscription | Intune |
| Vendor support utility (laptop model) | Drivers / firmware | Free | Image |

## 2. Department add-ons

| Department | Software | Licence |
|---|---|---|
| Finance | Accounting software desktop client; e-banking via Edge | Vendor subscription (3 seats) |
| Human Resources | HR/payroll SaaS (browser) | Vendor subscription |
| Sales & Marketing | CRM (SaaS, browser + Outlook add-in) | Vendor subscription (5 seats) |
| Sales & Marketing – Marketing Specialist | Adobe Creative Cloud | 1 seat |
| Software Development | VS Code, Git, Docker Desktop, WSL2, JetBrains IDE (optional), client VPN clients | Docker Business / JetBrains as needed |
| Customer Support | Ticketing SaaS (browser), Teams Phone softphone | Vendor subscription |
| IT | RSAT, PowerShell 7, Windows Admin Center, Wireshark, PuTTY/OpenSSH, Sysinternals | Free / included |

## 3. Microsoft licence plan

| SKU | Qty | Assigned to | Why |
|---|---:|---|---|
| Microsoft 365 Business Premium | 20 | All users (group `LIC_M365_BusinessPremium`) | Office apps, Exchange, Teams, Intune, Entra ID P1 (Conditional Access), Defender for Business – everything needed for ≤ 300 users |
| Windows Server 2025 Standard (16-core) | 2 | TC-HV01 | Each licence covers 2 VMs when all cores are licensed; 3 VMs → 2 licences |
| Windows Server 2025 User CAL | 20 | All users | Required to access Windows Server (AD, file shares) |
| Exchange Online shared mailboxes | 3 | `support@`, `info@`, `accounts@` | Free (≤ 50 GB, no licence needed) |
| Break-glass cloud admin | 0 | `bg-admin01` | Global Admin needs no licence; excluded from CA, monitored |

Licences are tracked in `11-it-asset-management/software-licenses/` (Phase 11).

## 4. Not allowed

| Category | Example | Reason |
|---|---|---|
| Personal cloud storage clients | Dropbox, Google Drive (personal) | Data leaves company control (BR-03, BR-26) |
| Unapproved remote-access tools | Consumer remote-desktop apps | Common attack vector; IT uses approved tools only |
| Pirated / unlicensed software | – | Legal and malware risk (BR-27) |
| Browser extensions outside the allow-list | – | Data exfiltration risk; managed via Edge policy |
