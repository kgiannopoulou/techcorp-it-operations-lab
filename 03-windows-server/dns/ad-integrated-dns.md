# AD-Integrated DNS and the Switch-Over from the Firewall Resolver

| Field | Value |
|---|---|
| Document ID | WIN-PRC-003 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved after the first lab build |
| Last reviewed | 2026-11-27 |
| Related requirements | BR-01, BR-15, BR-19 |

## Purpose

Complete the *Phase 2* half of the [DNS design](../../02-network-infrastructure/dns/dns-design.md):
the domain controllers become the DNS servers for every internal client, and
the firewall resolver is demoted to "guests + forwarder for the DCs".

## Target state

| Zone | Type | Replication scope | Dynamic updates | Contents |
|---|---|---|---|---|
| `corp.techcorp.example` | AD-integrated primary | All DNS servers in the domain | Secure only | DCs, servers, clients (self-registered), infrastructure A records |
| `_msdcs.corp.techcorp.example` | AD-integrated primary | All DNS servers in the forest | Secure only | DC locator records (created by promotion) |
| `10.10.10.in-addr.arpa` … `.40`, `.60` | AD-integrated reverse | Domain | Secure only | PTR records |

| Setting | Value | Why |
|---|---|---|
| Forwarder | `10.10.30.1` (TC-FW01 resolver), root hints **off** | One DNS egress point, filtering later (Phase 9); DCs need no outbound 53 |
| Scavenging | On, 7-day no-refresh + 7-day refresh | 14 days ≥ the 8-day STAFF lease, so live records are never removed |
| DHCP option 6 | `10.10.30.11, 10.10.30.12` for MGMT, STAFF and VPN | Domain members must use AD DNS |
| Guests | Still `10.10.50.1` | Guests never query internal DNS |

## Prerequisites

- [ ] Both DCs promoted and replicating – [ad-ds-deployment.md](../active-directory/ad-ds-deployment.md)
- [ ] Change recorded: client DNS change affects every VLAN (do it outside business hours)

## Procedure

1. **Forwarder and root hints** (on TC-DC01; repeat on TC-DC02 or with `-ComputerName`).

   ```powershell
   foreach ($dc in 'TC-DC01', 'TC-DC02') {
       Set-DnsServerForwarder -ComputerName $dc -IPAddress 10.10.30.1 -UseRootHint $false
   }
   ```

2. **Reverse zones.**

   ```powershell
   '10.10.10.0/24','10.10.20.0/24','10.10.30.0/24','10.10.40.0/24','10.10.60.0/24' | ForEach-Object {
       Add-DnsServerPrimaryZone -NetworkId $_ -ReplicationScope Domain -DynamicUpdate Secure
   }
   ```

3. **Infrastructure records** – move the pfSense host overrides into AD DNS
   (with PTRs). Devices that cannot register themselves need static records.

   ```powershell
   $records = @{
       'tc-fw01' = '10.10.10.1';  'tc-sw01' = '10.10.10.2';  'tc-ups01' = '10.10.10.5'
       'tc-ap01' = '10.10.10.11'; 'tc-ap02' = '10.10.10.12'; 'tc-ap03' = '10.10.10.13'
       'tc-hv01' = '10.10.30.10'; 'tc-nas01' = '10.10.30.30'
       'tc-prn01' = '10.10.40.10'; 'tc-prn02' = '10.10.40.11'
   }
   foreach ($name in $records.Keys) {
       Add-DnsServerResourceRecordA -ZoneName 'corp.techcorp.example' -Name $name -IPv4Address $records[$name] -CreatePtr
   }
   ```

4. **Scavenging.**

   ```powershell
   Set-DnsServerScavenging -ComputerName TC-DC01 -ScavengingState $true -ScavengingInterval 7.00:00:00 -ApplyOnAllZones
   Set-DnsServerZoneAging -Name 'corp.techcorp.example' -Aging $true -NoRefreshInterval 7.00:00:00 -RefreshInterval 7.00:00:00
   ```

   Only TC-DC01 scavenges (one scavenger is enough and easier to reason about).
   Static records from step 3 have no timestamp and are never scavenged.

5. **Firewall: domain override and clean-up** (pfSense *Services → DNS Resolver*).
   - Enable the prepared **Domain Override** `corp.techcorp.example` → `10.10.30.11`, `10.10.30.12`.
   - Delete the `corp.techcorp.example` **Host Overrides** – the AD zone is now authoritative (two sources of truth drift apart).
   - Add a Domain Override for `10.10.in-addr.arpa` → the DCs (reverse lookups from the firewall).

6. **Switch the clients** – *Services → DHCP Server* → MGMT, STAFF and the VPN
   pool: DNS servers `10.10.30.11`, `10.10.30.12`
   ([dhcp-configuration.md](../../02-network-infrastructure/dhcp/dhcp-configuration.md)).
   Clients pick it up at renewal; in the lab run `ipconfig /renew`.

7. **Servers**: TC-FS01 and the NAS use `10.10.30.11`, `10.10.30.12` (static).

## Verification

```powershell
Resolve-DnsName _ldap._tcp.dc._msdcs.corp.techcorp.example -Type SRV   # two DCs
Resolve-DnsName tc-sw01.corp.techcorp.example                          # 10.10.10.2 (from AD now)
Resolve-DnsName 10.10.10.2                                              # PTR tc-sw01
Resolve-DnsName www.microsoft.com -Server 10.10.30.11                   # forwarder works
Get-DnsClientServerAddress -AddressFamily IPv4                          # client uses .11 / .12
Test-NetConnection 10.10.30.11 -Port 53
```

| Check | Expected |
|---|---|
| From STAFF | All of the above succeed; `Test-TechCorpNetwork.ps1 -Include Servers` DNS tests pass |
| From GUEST | Public names resolve via 10.10.50.1; `10.10.30.11:53` is **blocked** |
| Stop TC-DC01 | Clients still resolve via TC-DC02 (second option 6 entry) |

## Rollback

Set DHCP option 6 back to the firewall interface address, re-enable the host
overrides, disable the domain override, `ipconfig /renew` on clients. AD
zones can stay – nothing uses them.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Internet names fail, internal names work | Forwarder unreachable | `Test-NetConnection 10.10.30.1 -Port 53` from the DC; SERVERS rule 1 |
| A client's record has the wrong IP | Stale record, scavenging not yet run | `ipconfig /registerdns` on the client; remove stale record |
| PTR missing | Reverse zone missing or client registered before it existed | Step 2, then `ipconfig /registerdns` |
| Firewall still answers an old IP for `tc-xx` | Host override left in place | Step 5 |

## Evidence

`15-documentation/screenshots/phase-02/`: DNS Manager zone list, forwarders
tab, pfSense domain overrides, `Resolve-DnsName` output from STAFF and GUEST.

## References

- [DNS scavenging](https://learn.microsoft.com/troubleshoot/windows-server/networking/dns-scavenging-setup)
- [DNS client settings on domain controllers](https://learn.microsoft.com/troubleshoot/windows-server/networking/best-practices-for-dns-client-settings)
