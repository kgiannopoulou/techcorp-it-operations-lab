# Company Profile – TechCorp Solutions

| Field | Value |
|---|---|
| Document ID | CO-REF-001 |
| Owner | IT Specialist |
| Status | Approved |
| Last reviewed | 2026-11-26 |

> **TechCorp Solutions is fictional.** It is a realistic small business used to
> practise building and running an IT department from zero.

## 1. Who TechCorp is

| Item | Detail |
|---|---|
| Legal name | TechCorp Solutions S.A. (fictional) |
| Sector | Custom software development and IT consulting for SMEs |
| Founded | 2021 |
| Employees | 20 (after the 2027 expansion) |
| Location | One office, 3rd floor, ~260 m², Athens, Greece (fictional address) |
| Working hours | Mon–Fri 08:30–17:30 EET; customer support until 18:00 |
| Working model | Hybrid – 8 people office-based, 12 hybrid (2–3 office days/week) |
| Customers | ~40 SME clients; Customer Support handles their tickets by e-mail and phone |
| Annual IT budget | Initial deployment capex ≈ €72 000, then ≤ €18 000/year opex (see [business requirements](business-requirements.md)) |

## 2. The situation on my first day

TechCorp grew from 6 founders to 20 people in three years **without an IT
department**. The current state is typical of a fast-growing small company:

| Area | Current state ("as-is") | Problem |
|---|---|---|
| Devices | Mix of personal and company laptops, no standard, Windows Home on several | No central management, no BitLocker, can't join a domain |
| Accounts | Shared Gmail mailboxes, personal accounts for SaaS tools | No offboarding control, no MFA, data owned by individuals |
| Files | Files on laptops, USB sticks and personal Dropbox | No backup, no permissions, data-loss risk |
| Network | ISP router with default Wi-Fi password, one flat network | Guests and printers on the same network as finance data |
| Printing | One consumer inkjet shared via USB | Unreliable, no scanning to e-mail |
| Support | "Ask the developer who knows computers" | Developers lose time; nothing documented |
| Security | No antivirus standard, no patching policy, no backups | Ransomware or a lost laptop would be a serious incident |

The company has signed a lease for a **new, larger office** and is moving in
on **Monday 15 February 2027**. I join as the **first IT Specialist** on
**Monday 4 January 2027** – six weeks to plan and deploy everything.

## 3. What management wants

The CEO's brief, in their words:

> "When we move into the new office, I want everything to *just work*: secure
> Wi-Fi, proper company e-mail, one login per person, files that are backed up,
> printers that work, and someone people can actually ask for help. And I
> don't want to be the next company in the news for a ransomware attack."

These are translated into measurable requirements in
[business-requirements.md](business-requirements.md).

## 4. Target environment ("to-be") summary

| Area | Target |
|---|---|
| Identity | On-prem AD DS (`corp.techcorp.example`) synchronised to Microsoft Entra ID (hybrid identity) |
| Productivity | Microsoft 365 Business Premium for all 20 users |
| Devices | 20 standard Windows 11 Pro laptops + 2 spares, docked at hot desks, BitLocker, managed by GPO + Intune |
| Network | Business firewall, managed PoE switch, 3 Wi-Fi APs, 5 VLANs (management, staff, servers, printers, guest) |
| Servers | 1 Hyper-V host: 2 domain controllers + 1 file server (VMs) |
| Backup | Local NAS + offsite cloud copy (3-2-1) and Microsoft 365 backup |
| Support | Ticketed helpdesk via `support@techcorp.example`, documented SLAs |
| Security | MFA everywhere, Defender for Business, patching cadence, least privilege |

Full design: [01-office-deployment](../01-office-deployment/) and
[02-network-infrastructure](../02-network-infrastructure/).
