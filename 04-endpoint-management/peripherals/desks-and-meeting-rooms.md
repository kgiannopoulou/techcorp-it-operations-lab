# Desks, Docks, Headsets and Meeting Rooms

| Field | Value |
|---|---|
| Document ID | END-PRC-005 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved after installation |
| Last reviewed | 2026-11-27 |
| Related requirements | BR-04, BR-07 |

## 1. Hot desks (24)

Every desk is identical ([desk standard](../../01-office-deployment/workstation-deployment/workstation-standard.md#2-desk-standard-identical-at-all-24-desks)):
dock → wall drop (VLAN 20), 2 monitors on the dock's DisplayPort outputs,
wired keyboard and mouse.

| Check (per desk, at installation and quarterly) | Pass |
|---|---|
| Laptop charges from the dock (100 W) | Battery icon shows charging |
| Both monitors extend the desktop at 1080p | *Settings → Display* shows 3 displays |
| Wired network via dock | `Get-NetAdapter` → dock NIC *Up*, address 10.10.20.x |
| Dock firmware at the fleet baseline | Vendor dock tool |
| Asset tags match the inventory (`TC-DCK-NN`, `TC-MON-NNN`) | Visual + inventory row |

Hot-desking rule: nothing personal is stored on the laptop that isn't in
OneDrive (Known Folder Move) – a broken laptop is swapped for a spare in
under an hour (BR-04).

## 2. Headsets

Teams-certified USB headsets (`TC-HS-001` … `004`): Customer Support has two
assigned, two spares. Set in Teams → *Settings → Devices*; firmware via the
vendor app. Test with Teams' *Make a test call*.

## 3. Meeting rooms (Teams Rooms)

| Room | Kit | Resource account | Capacity |
|---|---|---|---:|
| Meeting Room 1 | TC-MR-001 video bar + 55″ display | `room-mr1@techcorp.example` | 8 |
| Meeting Room 2 | TC-MR-002 video bar + 55″ display | `room-mr2@techcorp.example` | 4 |

1. Resource accounts are **room mailboxes** created from
   [mailboxes.csv](../../05-microsoft-365/exchange-online/mailboxes.csv) by
   `Deploy-TechCorpM365.ps1` (auto-accept, no double booking, 180-day window).
2. Enable the account for sign-in (room mailboxes are disabled by default),
   set a long password stored in the password manager, exclude it from
   password expiry, and assign a **Teams Rooms Basic** licence (free for up to
   25 rooms) – it is not part of `LIC_M365_BusinessPremium`.
3. Sign the video bar in with the resource account (Teams Rooms on Android:
   on-device sign-in). The device is on a STAFF port with a DHCP reservation.
4. Test: book the room from Outlook → it accepts; start the meeting from the
   room console; share a laptop screen via HDMI ingest and via Teams.

Conditional Access treatment for shared devices (exclude from MFA, require
compliant device + trusted location) is designed in M7.
