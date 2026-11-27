# SC-WIN-001: New laptop cannot join the domain

| Field | Value |
|---|---|
| Scenario ID | SC-WIN-001 |
| Category | Windows |
| Difficulty | ⭐ |
| Priority (if real) | P3 – single user, new starter on day 1 |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | VirtualBox: TC-DC01, TC-FW01-LAB, TC-LT-LAB01 on `tc-vlan20` |

## 1. The report

> *"Joining TC-LT-021 to corp.techcorp.example says 'An Active Directory Domain Controller for the domain could not be contacted'. The network is fine – I can browse the web."* – IT Specialist's own note while preparing a spare laptop

## 2. Environment / context

Spare laptop TC-LT-021, freshly imaged, on a STAFF desk port. Internet works.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

The STAFF DHCP scope on TC-FW01 still hands out the firewall (`10.10.20.1`) as DNS server – the Phase 2 option 6 change ([ad-integrated-dns.md](../../03-windows-server/dns/ad-integrated-dns.md) step 6) was skipped for STAFF.

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Can the client reach the DC at all? | `Test-NetConnection 10.10.30.11 -Port 389` | `TcpTestSucceeded : True` | Network and firewall are fine |
| 2 | Which DNS server does it use? | `Get-DnsClientServerAddress -AddressFamily IPv4` | `10.10.20.1` | Not a DC |
| 3 | Can it find a DC by DNS? | `Resolve-DnsName _ldap._tcp.dc._msdcs.corp.techcorp.example -Type SRV` | Name does not exist | The firewall resolver doesn't know the AD zone's SRV records |
| 4 | Same query against the DC | `… -Server 10.10.30.11` | Two SRV records | AD DNS is healthy – the client is asking the wrong server |
| 5 | DHCP lease detail | `ipconfig /all` → *DNS Servers*, *DHCP Server* | Option 6 from 10.10.20.1 | Scope misconfiguration |

## 5. Root cause

Domain join locates a DC through DNS SRV records in `_msdcs.corp.techcorp.example`.
The client's DNS server (the firewall) has no such records.

## 6. Resolution

1. TC-FW01 → *Services → DHCP Server → STAFF* → DNS servers `10.10.30.11`, `10.10.30.12`.
2. Client: `ipconfig /renew`, then join as `wadm-eren.yeager`:
   `Add-Computer -DomainName corp.techcorp.example -Credential TECHCORP\wadm-eren.yeager -Restart`.

## 7. Verification

`nltest /dsgetdc:corp.techcorp.example` returns TC-DC01 or TC-DC02; the computer
object appears in `TechCorp/Computers/Workstations/Standard` (redircmp).

## 8. Prevention

- `Test-TechCorpNetwork.ps1 -Include Servers` after every DHCP change.
- Never "fix" it by putting the DC's IP in the client's static settings – that hides a scope problem for every other laptop.

## 9. Skills practised

- How DC location works (DNS SRV, `nltest`)
- DHCP option 6 and its effect on domain membership

## 10. Related

- [ad-troubleshooting.md](../../03-windows-server/active-directory/ad-troubleshooting.md)
- [SC-NET-004](../networking/sc-net-004-internet-by-ip-not-by-name.md) – same option, different symptom
