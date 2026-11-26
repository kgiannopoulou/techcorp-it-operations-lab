# SC-NET-004: Teams call keeps working but no website opens

| Field | Value |
|---|---|
| Scenario ID | SC-NET-004 |
| Category | Networking |
| Difficulty | ⭐ |
| Priority (if real) | P2 – department impact |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | [Packet Tracer lab](../../02-network-infrastructure/packet-tracer-lab/) / VirtualBox lab |

## 1. The report

> *"Websites just spin and say DNS_PROBE_FINISHED_NXDOMAIN, but my Teams call did not drop."* – Sasha Blouse, HR & Office Coordinator

## 2. Environment / context

All STAFF clients that renewed their lease this morning. Existing Teams media flows use IP addresses that were resolved earlier.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

The STAFF DHCP pool hands out DNS server `10.10.30.99` (typo) instead of the correct server.

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Ping by IP | `ping 1.1.1.1` | Replies | Routing and NAT are fine |
| 2 | Resolve a name | `Resolve-DnsName microsoft.com` | Timeout | DNS is the problem |
| 3 | Client DNS server | `Get-DnsClientServerAddress` | 10.10.30.99 | Wrong server handed out |
| 4 | DHCP scope | `show ip dhcp pool` | dns-server 10.10.30.99 | Scope misconfigured |

## 5. Root cause

Wrong DNS server in the STAFF DHCP scope.

## 6. Resolution

1. Correct the DNS server option in the scope.
2. On clients: `ipconfig /renew` (or wait for renewal), then `ipconfig /flushdns`.

## 7. Verification

`Resolve-DnsName microsoft.com` answers; the Test-TechCorpNetwork DNS tests pass.

## 8. Prevention

- Peer-check scope changes; run Test-TechCorpNetwork after every DHCP/DNS change.

## 9. Skills practised

- Ping-by-IP vs ping-by-name split
- DHCP options

## 10. Related

- [dns-design.md](../../02-network-infrastructure/dns/dns-design.md)
- [network-troubleshooting.md](../../02-network-infrastructure/troubleshooting/network-troubleshooting.md)
