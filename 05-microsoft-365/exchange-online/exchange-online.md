# Exchange Online: Domain, Mail Security, Shared Mailboxes and Mail Flow

| Field | Value |
|---|---|
| Document ID | M365-PRC-004 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved after the lab tenant is built |
| Last reviewed | 2026-11-27 |
| Related requirements | BR-02, BR-06, BR-17, BR-26 |
| Source data | [mailboxes.csv](mailboxes.csv) |

## 1. Mailboxes

| Address | Type | Full Access + Send As | Purpose |
|---|---|---|---|
| `firstname.lastname@` × 20 | User (licensed) | – | Personal mail, 50 GB + archive |
| `support@` | Shared | petra.ral, oluo.bozado | Client tickets (BR-02) |
| `info@` | Shared | hange.zoe, sasha.blouse | Website enquiries |
| `accounts@` | Shared | dot.pixis, nile.dok, hitch.dreyse | Invoices – Finance only (CI-checked) |
| `dmarc@` | Shared | eren.yeager (Full Access only) | DMARC aggregate reports |
| `room-mr1@` / `room-mr2@` | Room (8 / 4 seats) | – | Teams Rooms, auto-accept |

Full Access is granted **per user with auto-mapping**, so the mailbox appears
in Outlook by itself. (Granting it through a group works for access but
disables auto-mapping – SC-M365-005.)

## 2. Domain and DNS (production)

Published in this order on the public DNS host (values in
[dns-design.md §4](../../02-network-infrastructure/dns/dns-design.md#4-public-dns-records-microsoft-365)):

1. TXT verification → domain *Verified*.
2. `autodiscover` CNAME, SPF TXT, DKIM CNAMEs (`selector1`/`selector2`).
3. Enable DKIM: `Set-DkimSigningConfig -Identity techcorp.example -Enabled $true` (done by `Deploy-TechCorpM365.ps1`).
4. DMARC `p=none` for two weeks, read the reports in `dmarc@`, then `p=quarantine`.
5. **MX last** – this is the cut-over moment for inbound mail (lower TTL to 300 s a week before).

## 3. Mail security

| Setting | Value | How |
|---|---|---|
| Preset security policy | **Standard protection** for all users (anti-spam, anti-phishing, Safe Links, Safe Attachments – Defender for Office 365 P1 is in BP) | *Defender portal → Email & collaboration → Preset security policies* |
| External sender tag | On – "External" label in Outlook | `Set-ExternalInOutlook -Enabled $true` |
| Auto-forwarding to external addresses | **Blocked** (outbound spam policy default *Automatic – system controlled* = off) | Defender portal → Anti-spam outbound policy |
| Mailbox auditing | On by default; confirm `Get-OrganizationConfig \| Select AuditDisabled` = False | – |
| SMTP AUTH (basic) | Disabled org-wide: `Set-TransportConfig -SmtpClientAuthenticationDisabled $true` | Printers use the connector (§5) |
| Report message button | Built into new Outlook / OWA; reports go to Microsoft and to IT (a dedicated reporting mailbox follows in Phase 9 – never `support@`, which is for clients) | Defender portal → User reported settings |

## 4. Creating the mailboxes

```powershell
Connect-ExchangeOnline
.\07-powershell\microsoft-365\Deploy-TechCorpM365.ps1 -Skip Users,Licensing,Teams,SharePoint -WhatIf
.\07-powershell\microsoft-365\Deploy-TechCorpM365.ps1 -Skip Users,Licensing,Teams,SharePoint
```

Lab: add `-LabTenant -TenantDomain <tenant>.onmicrosoft.com` – addresses become `support@<tenant>.onmicrosoft.com`.

## 5. Scan-to-e-mail from TC-PRN01 (M365-CHG-001)

The M4 firewall rule assumed the MFP would log in to `smtp.office365.com:587`
with a mailbox password (**SMTP AUTH client submission**). That needs basic
authentication, which Microsoft is retiring for SMTP AUTH and which we
disable tenant-wide (§3) – and it would put a mailbox password into the
printer's web UI.

**M365-CHG-001 – SMTP relay through a connector:**

| Piece | Value |
|---|---|
| Printer SMTP server | `techcorp-example.mail.protection.outlook.com`, port **25**, STARTTLS, no authentication |
| From address | `scanner@techcorp.example` (no mailbox needed) |
| Exchange inbound connector | *From: Your organization's email server*, identified by the office's static public IP `203.0.113.10` |
| SPF | `v=spf1 ip4:203.0.113.10 include:spf.protection.outlook.com -all` |
| Firewall (pfSense) | PRINTERS rule 3: TCP **25** to alias `HOST_EXO_MX` (FQDN alias of the MX host) – replaces "587 to any" |

```powershell
New-InboundConnector -Name 'TC-PRN01 scan-to-email' -ConnectorType OnPremises `
    -SenderIPAddresses 203.0.113.10 -RestrictDomainsToIPAddresses $true -SenderDomains 'techcorp.example' -RequireTls $true
```

Lab: no static public IP and no verified domain – test scan-to-e-mail with a
PowerShell sender from the PRINTERS VLAN to the lab tenant's MX (direct send
to internal recipients) and record that the connector path is production-only.

## 6. Migration from the shared Gmail mailboxes

The company currently uses shared Gmail mailboxes ([company-profile.md](../../00-company-overview/company-profile.md)).

1. Inventory each Gmail mailbox → new owner (support/info/accounts shared mailbox or a person).
2. Create app passwords on the Gmail accounts (IMAP), CSV of mappings.
3. *Exchange admin center → Migration → IMAP migration* batch into the new mailboxes; keep it syncing until the MX cut-over.
4. After MX cut-over: complete the batch, set Gmail auto-reply "we have moved", keep the Gmail accounts read-only for 90 days, then close them (offboarding control, BR-10).

## Verification

| Test | Expected |
|---|---|
| `Test-TechCorpM365.ps1` Mail rows | PASS |
| petra.ral opens Outlook | `support@` listed under her mailbox (auto-mapped) |
| Petra sends **as** support@ | Recipient sees *TechCorp Support* |
| connie.springer tries `accounts@` in OWA | No access |
| Mail from an external address | "External" tag shown |
| Headers of an outbound mail (production) | `spf=pass`, `dkim=pass`, `dmarc=pass` |

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Shared mailbox not in Outlook | Auto-mapping delay (up to 60 min) or access granted via group | Wait / grant per user (SC-M365-005) |
| "Send As" fails with NDR | Send As not granted, or Outlook cached the old permission | `Get-EXORecipientPermission`; restart Outlook |
| Scans don't arrive / land in Junk | Connector IP, SPF missing the public IP | SC-M365-002 |
| Room never accepts | `AutomateProcessing` not AutoAccept | `Set-CalendarProcessing room-mr1 -AutomateProcessing AutoAccept` |
| Mail to Gmail bounces after cut-over | DMARC/SPF wrong | Check with the Microsoft Remote Connectivity Analyzer |
