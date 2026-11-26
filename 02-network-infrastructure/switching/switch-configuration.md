# Switch Configuration – TC-SW01

| Field | Value |
|---|---|
| Document ID | NET-PRC-002 |
| Owner | IT Specialist |
| Status | Draft – validated subset in Packet Tracer pending |
| Last reviewed | 2026-11-26 |
| Related requirements | BR-15, BR-19 |

## Purpose

Configure the single 48-port PoE+ switch so that every port does exactly one
job, unused ports are dead, and common layer-2 attacks or accidents (rogue
DHCP server, loop, user plugging in a switch) are contained.

## Files

| File | What it is |
|---|---|
| [switch-port-plan.csv](switch-port-plan.csv) | **Source of truth** – one row per port: mode, VLANs, PoE, drop, device. Validated in CI |
| [tc-sw01.cfg](tc-sw01.cfg) | Full IOS-XE configuration generated from the CSV (secrets `<REDACTED>`) |

## 1. Port groups

| Ports | Role | Mode | VLAN | Protection |
|---|---|---|---|---|
| 1–24 | Desk docks D-01 – D-24 | Access | 20 | PortFast, BPDU guard, storm control, DHCP rate-limit |
| 25, 27 | Meeting-room video bars | Access | 20 | Same as desks; PoE |
| 26, 28 | Meeting-room table ports | Access | **50** | Visitors can reach them → guest VLAN ([NET-CHG-002](#change-net-chg-002)) |
| 29–31 | Wi-Fi APs | Trunk | native 10, allowed 10,20,50 | PoE+ |
| 32–33 | Printers | Access | 40 | PortFast, BPDU guard, storm control |
| 34–40 | Spare | Access | 999 | **shutdown** |
| 41 | Firewall uplink | Trunk | native 999, allowed 10,20,30,40,50 | **DHCP snooping trusted** |
| 42–43 | Hyper-V host (SET team) | Trunk | native 999, allowed 10,30 | – |
| 44 | iDRAC | Access | 10 | PortFast |
| 45–46 | NAS | LACP → Port-channel1 | 30 | – |
| 47 | UPS card | Access | 10 | PortFast |
| 48 | IT service port | Access | 10 | PortFast |

## 2. Procedure (new switch out of the box)

1. **Console in** (USB/RJ45 console, 9600 8N1) and abort the initial setup dialog.
2. **Paste the base section** of `tc-sw01.cfg` (hostname → VLANs → spanning
   tree), replacing every `<REDACTED>` with a password from the password manager.
3. **Generate SSH keys** (exec mode, once):

   ```text
   TC-SW01(config)# crypto key generate rsa modulus 3072
   ```

4. **Paste the interface section.** Ports 34–40 come up `administratively down`.
5. **Paste the management section** (SVI VLAN 10, default gateway, SSH, ACL, NTP, banner).
6. **Save:** `copy running-config startup-config`.
7. **Back up the config** off the switch (`show running-config` → saved,
   *sanitised*, into the IT password-protected share; never into this public repo with secrets).

   *Expected result:* SSH from the IT service port (VLAN 10) works; SSH from VLAN 20 is refused.

## 3. Why each hardening feature

| Feature | Protects against | Note |
|---|---|---|
| `spanning-tree mode rapid-pvst` + priority 4096 | Slow convergence; another switch becoming root | Root is always TC-SW01 |
| `spanning-tree portfast` | Laptop waits 30 s for an IP after docking | Access ports only |
| `spanning-tree bpduguard enable` | Someone plugs a home switch/hub into a desk drop → loop | Port goes `err-disabled`, auto-recovers after 300 s |
| `storm-control broadcast level 5.00` | Broadcast storm from a faulty NIC | Sends SNMP trap/log |
| `ip dhcp snooping` (VLANs 10/20/50), trust only Gi1/0/41 | **Rogue DHCP server** (e.g. a consumer router plugged in) | Only the firewall may hand out leases |
| `no ip dhcp snooping information option` | Switch inserts option 82, some DHCP servers then drop requests | Classic gotcha – remove option 82 insertion |
| `ip dhcp snooping limit rate 15` | DHCP starvation attack | Port err-disables above 15 pps |
| `switchport nonegotiate` | DTP trunk negotiation by an attacker | Everywhere |
| Native VLAN 999 on trunks | VLAN-hopping via double tagging | 999 carries nothing |
| Unused ports shutdown in VLAN 999 | Walk-up access from a spare drop | Enabled only via a ticket |
| `ACL-MGMT-SSH` on vty, SSH v2 only | Management from user VLANs, Telnet sniffing | |
| `Vlan1` shutdown, no IP | Default-VLAN exposure | |

## 4. Verification

```text
show vlan brief
show interfaces trunk
show interfaces status
show spanning-tree summary
show ip dhcp snooping
show etherchannel summary
show power inline
show interfaces status err-disabled
```

| Check | Expected |
|---|---|
| `show interfaces status` | Ports 34–40 `disabled`, others `connected`/`notconnect` in the right VLAN |
| `show spanning-tree vlan 20` | "This bridge is the root" |
| `show ip dhcp snooping` | Enabled on 10, 20, 50; Gi1/0/41 trusted |
| `show etherchannel summary` | Po1 (SU) with Gi1/0/45 + 46 (P) |
| `show power inline` | APs drawing power on 29–31 |

## 5. Rollback

The previous config is kept as `flash:backup-YYYYMMDD.cfg` before any change:

```text
copy running-config flash:backup-20270111.cfg
! ...change goes wrong...
configure replace flash:backup-20270111.cfg
```

## Change NET-CHG-002

While writing scenario [SC-NET-003](../../14-scenarios/networking/sc-net-003-guest-reaches-internal.md)
I realised the Milestone 3 plan put the meeting-room **table ports** (D-26, D-28)
in the staff VLAN, so any visitor with a cable would be on VLAN 20 with access
to the file server. Both ports moved to **VLAN 50 (guest)** in the port plan,
the cabling plan and `tc-sw01.cfg`. The video bars stay in VLAN 20.

## 6. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Desk port goes `err-disabled` | BPDU guard – user connected a switch | `show interfaces status err-disabled`, remove device, `shutdown` / `no shutdown` |
| Laptop takes 30+ s to get an IP | PortFast missing on that port | Add `spanning-tree portfast` |
| Clients get a 192.168.x.x address | Rogue DHCP; snooping not enabled on that VLAN | Find the port with `show ip dhcp snooping binding`, enable snooping |
| No DHCP at all after enabling snooping | Uplink not trusted, or option 82 inserted | `ip dhcp snooping trust` on Gi1/0/41; `no ip dhcp snooping information option` |
| NAS slow / flapping | LACP mismatch (NAS in balance-alb mode) | Set NAS bond to 802.3ad |
