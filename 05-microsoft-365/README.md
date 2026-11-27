# 05 – Microsoft 365

**Status:** ✅ Milestone 6 – accounts, e-mail, Teams, SharePoint/OneDrive designed, scripted and documented · 🧪 lab tenant pending · ⏳ Intune, MFA/Conditional Access in M7

Microsoft 365 Business Premium for 20 people: one identity synced from AD,
group-based licensing, Exchange Online, Teams with dynamic membership,
SharePoint and OneDrive. Like `03-windows-server`, the design is **data**
(CSVs) validated in CI and applied by scripts in
[07-powershell/microsoft-365](../07-powershell/microsoft-365/).

## Build order

| # | Document | ID | Result |
|---|---|---|---|
| 1 | [tenant/tenant-setup.md](tenant/tenant-setup.md) | M365-PRC-001 | Tenant, break-glass + cloud admin, org settings, security defaults |
| 2 | [entra-connect/entra-connect-sync.md](entra-connect/entra-connect-sync.md) | M365-PRC-002 | Users, licensing group and laptops synced; hybrid join |
| 3 | [user-management/licensing-and-lifecycle.md](user-management/licensing-and-lifecycle.md) | M365-PRC-003 | Licences via group, joiner/mover/leaver in the cloud |
| 4 | [exchange-online/exchange-online.md](exchange-online/exchange-online.md) | M365-PRC-004 | DNS, DKIM/DMARC, shared + room mailboxes, mail security, scan-to-e-mail, Gmail migration |
| 5 | [teams/teams.md](teams/teams.md) | M365-PRC-005 | 7 teams with dynamic membership, channels, tenant policies |
| 6 | [sharepoint/sharepoint-and-onedrive.md](sharepoint/sharepoint-and-onedrive.md) | M365-PRC-006 | Site sharing levels, intranet, OneDrive KFM and sync restriction |

## Source data (CI-validated by `Get-TechCorpM365Plan.ps1 -SelfTest`)

| File | Contents |
|---|---|
| [tenant/cloud-admins.csv](tenant/cloud-admins.csv) | 2 break-glass + 1 daily cloud admin, roles |
| [exchange-online/mailboxes.csv](exchange-online/mailboxes.csv) | 4 shared + 2 room mailboxes, Full Access / Send As |
| [teams/teams.csv](teams/teams.csv) | 7 teams: department rule, owners, channels, guest access |
| [sharepoint/sites.csv](sharepoint/sites.csv) | 8 sites and their external sharing level |

Plus from M5: `EntraSync` column in [ou-structure.csv](../03-windows-server/users-and-groups/ou-structure.csv)
and `LIC_M365_BusinessPremium` in [ad-groups.csv](../03-windows-server/users-and-groups/ad-groups.csv).

## Lab constraint

`techcorp.example` can never be verified in a real tenant (RFC 2606). The lab
uses the tenant's `onmicrosoft.com` domain: every script takes `-LabTenant
-TenantDomain <tenant>.onmicrosoft.com`. DNS cut-over, DKIM and the printer
connector are documented but production-only.

## Design changes in Milestone 6

| ID | Change | Why |
|---|---|---|
| [M365-CHG-001](exchange-online/exchange-online.md#5-scan-to-e-mail-from-tc-prn01-m365-chg-001) | Scan-to-e-mail via inbound connector on port 25 (was SMTP AUTH 587) | Basic-auth SMTP AUTH is being retired and is disabled tenant-wide |
| [M365-CHG-002](entra-connect/entra-connect-sync.md#design-change-m365-chg-002--the-disabled-ou-is-synced) | `TechCorp/Disabled` is in the sync scope | Moving a leaver out of scope deletes the cloud account and orphans the mailbox |

## Planned for M7

| Folder | Contents |
|---|---|
| `entra-id/` | MFA (phishing-resistant for admins), Conditional Access replacing security defaults, SSPR + password writeback |
| `intune/` | Enrolment of the hybrid-joined fleet, compliance, BitLocker/Defender/update-ring profiles, Autopilot for refreshes |
