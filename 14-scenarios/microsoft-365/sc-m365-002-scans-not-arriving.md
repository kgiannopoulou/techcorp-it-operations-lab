# SC-M365-002: Scans from the printer never arrive

| Field | Value |
|---|---|
| Scenario ID | SC-M365-002 |
| Category | Microsoft 365 |
| Difficulty | ⭐⭐ |
| Priority (if real) | P3 – department impact, workaround (scan to USB is blocked for Finance) |
| Status | Designed – expected investigation written; **production-only path** – lab can test the message trace part only |
| Lab | Lab tenant message trace; production: TC-PRN01, pfSense |

## 1. The report

> *"I scan invoices to myself every day. Since Monday nothing comes through – the printer says 'sent'."* – Nile Dok, Accountant

## 2. Environment / context

On Monday the ISP replaced the router; the office's public IP changed from 203.0.113.10 to 203.0.113.11 (both fictional). Nobody updated the connector or SPF.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

Change the inbound connector's `SenderIPAddresses` to an address the lab doesn't use, then send a test message "from the printer" with `Send-MailMessage` style SMTP from the lab network.

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Did it reach Exchange? | `Get-MessageTraceV2 -SenderAddress scanner@techcorp.example -StartDate (Get-Date).AddDays(-3)` | Rejected / *FilteredAsSpam*, or nothing | Accepted path is broken |
| 2 | Printer log | MFP web UI → SMTP log | `550 5.7.64 TenantAttribution; Relay Access Denied` | Exchange doesn't recognise the sender as us |
| 3 | Our public IP | `Invoke-RestMethod https://ifconfig.me` from the office | 203.0.113.11 | IP changed |
| 4 | Connector | `Get-InboundConnector 'TC-PRN01 scan-to-email' \| Select SenderIPAddresses` | 203.0.113.10 | Root cause |
| 5 | SPF | `Resolve-DnsName techcorp.example -Type TXT` | `ip4:203.0.113.10` | Also stale – scans to external addresses would fail SPF |

## 5. Root cause

The connector identifies the office by its public IP; the IP changed.

## 6. Resolution

Update the connector (`Set-InboundConnector … -SenderIPAddresses 203.0.113.11`)
and the SPF record; update [dns-design.md](../../02-network-infrastructure/dns/dns-design.md)
and the IP plan in the same change.

## 7. Verification

Scan to own address → arrives in Inbox; headers show `spf=pass`; message trace *Delivered*.

## 8. Prevention

"ISP / public IP change" checklist item in change management (Phase 12): connector, SPF, VPN DNS record, firewall WAN.

## 9. Skills practised

- Exchange message trace, connectors, SPF
- Following a dependency on an IP address across documents
