# Subnetting Guide and Exercises

| Field | Value |
|---|---|
| Document ID | NET-REF-003 |
| Owner | IT Specialist |
| Status | Approved |
| Last reviewed | 2026-11-26 |
| Tool | [Get-SubnetInfo.ps1](../../07-powershell/network-diagnostics/Get-SubnetInfo.ps1) – use it to check your answers |

## 1. The method I use (no calculator needed)

1. **Find the "interesting" octet**: the octet where the mask is not 255 or 0.
2. **Block size = 256 − mask value in that octet.** For `/26` the mask is
   `255.255.255.192`, so the block size is `256 − 192 = 64`.
3. **Networks start at multiples of the block size**: `.0, .64, .128, .192`.
4. The address belongs to the highest multiple that is ≤ the address.
5. **Broadcast = next network − 1. First host = network + 1. Last host = broadcast − 1.**
6. **Usable hosts = 2^(32 − prefix) − 2.**

### Worked example: `10.10.50.200/26`

| Step | Result |
|---|---|
| Interesting octet | 4th (mask `.192`) |
| Block size | 256 − 192 = **64** |
| Networks | .0, .64, .128, **.192** |
| 200 falls in | **10.10.50.192/26** |
| Broadcast | 10.10.50.255 |
| Host range | 10.10.50.193 – 10.10.50.254 |
| Usable hosts | 2⁶ − 2 = **62** |

Check it with the script:

```powershell
./07-powershell/network-diagnostics/Get-SubnetInfo.ps1 10.10.50.200/26
```

## 2. Cheat sheet

| Prefix | Mask | Block (last octet) | Usable hosts | Typical use |
|---:|---|---:|---:|---|
| /24 | 255.255.255.0 | 256 | 254 | A TechCorp VLAN |
| /25 | 255.255.255.128 | 128 | 126 | |
| /26 | 255.255.255.192 | 64 | 62 | Staff VLAN in a right-sized design |
| /27 | 255.255.255.224 | 32 | 30 | Management, VPN pool |
| /28 | 255.255.255.240 | 16 | 14 | Servers |
| /29 | 255.255.255.248 | 8 | 6 | Printers; ISP public block |
| /30 | 255.255.255.252 | 4 | 2 | Legacy point-to-point link |
| /31 | 255.255.255.254 | 2 | 2 (RFC 3021) | Modern point-to-point link |
| /32 | 255.255.255.255 | 1 | 1 | Single host route / loopback |

Private ranges (RFC 1918): `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`.
Documentation ranges (RFC 5737), safe for examples: `192.0.2.0/24`,
`198.51.100.0/24`, `203.0.113.0/24`. `169.254.0.0/16` is APIPA – a client
that shows it **did not get a DHCP lease**.

## 3. Why TechCorp uses /24s anyway

The production plan ([ip-addressing-plan.md](../ip-addressing/ip-addressing-plan.md))
uses one `/24` per VLAN with the third octet equal to the VLAN ID. With
`10.0.0.0/8` available, saving addresses has no value for 20 people, while
"`10.10.40.x` = printers" saves time in every troubleshooting session. The VLSM
exercise below shows I *can* right-size it when address space is scarce (for
example a branch office handed a single `/24` by head office).

## 4. VLSM exercise: TechCorp in a single /24

**Task:** head office gives a new branch only `172.16.0.0/24`. Fit these
networks in it, largest first, without overlaps.

| Network | Hosts needed | Prefix | Subnet | Host range | Broadcast |
|---|---:|---:|---|---|---|
| Staff | 60 | /26 (62) | 172.16.0.0/26 | .1 – .62 | .63 |
| Guest | 50 | /26 (62) | 172.16.0.64/26 | .65 – .126 | .127 |
| VPN | 30 | /27 (30) | 172.16.0.128/27 | .129 – .158 | .159 |
| Management | 20 | /27 (30) | 172.16.0.160/27 | .161 – .190 | .191 |
| Servers | 14 | /28 (14) | 172.16.0.192/28 | .193 – .206 | .207 |
| Printers | 6 | /29 (6) | 172.16.0.208/29 | .209 – .214 | .215 |
| *Free* | – | – | 172.16.0.216 – .255 | 40 addresses left for growth | |

Rules applied: allocate **largest first** so every block starts on its own
boundary; always leave free space at the end, not in gaps.
Lesson: VPN needs exactly 30 → a `/27` has zero headroom; in real life choose a `/26`.

## 5. Exercises

Answers are hidden – work them out first, then verify with `Get-SubnetInfo.ps1`.

1. `10.10.20.137/24` – network, broadcast, usable hosts?
2. `10.10.50.200/26` – network, first host, last host?
3. How many usable hosts in a `/28`?
4. Smallest prefix that fits 45 hosts?
5. `192.168.1.77/27` – network, host range, broadcast?
6. With a `/25`, are `10.10.20.10` and `10.10.20.130` in the same subnet?
7. What is the wildcard mask for a `/27` (used in Cisco ACLs)?
8. The ISP gives `203.0.113.10/29` with gateway `.9`. How many public IPs are left for us after the firewall uses `.10`?
9. Smallest single summary route covering every TechCorp subnet `10.10.10.0/24` … `10.10.60.0/24`?
10. `172.20.5.130/25` – network and host range?

<details>
<summary>Answers</summary>

| # | Answer |
|---|---|
| 1 | 10.10.20.0/24, broadcast 10.10.20.255, 254 hosts |
| 2 | 10.10.50.192/26, first .193, last .254 |
| 3 | 14 |
| 4 | /26 (62 hosts) – a /27 only gives 30 |
| 5 | 192.168.1.64/27, hosts .65 – .94, broadcast .95 |
| 6 | No – .10 is in 10.10.20.0/25, .130 is in 10.10.20.128/25 |
| 7 | 0.0.0.31 |
| 8 | Usable .9 – .14 (6); minus gateway .9 and firewall .10 → **4** (.11 – .14) |
| 9 | 10.10.0.0/18 (10.10.0.0 – 10.10.63.255). The plan simply uses 10.10.0.0/16 to leave room |
| 10 | 172.20.5.128/25, hosts .129 – .254 |

</details>
