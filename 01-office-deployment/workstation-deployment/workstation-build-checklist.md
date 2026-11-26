# Workstation Build Checklist

| Field | Value |
|---|---|
| Document ID | DEP-PRC-001 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved after first lab build (Phase 4) |
| Last reviewed | 2026-11-26 |

Use one copy of this checklist per laptop (copy into the ticket or a
deployment report). Settings are defined in
[workstation-standard.md](workstation-standard.md).

**Asset tag / hostname:** `TC-LT-___` · **Assigned to:** ________ · **Tier:** ________ · **Date:** ________

## A. Receive and record

- [ ] Box checked for damage; serial number recorded against the asset tag (asset register, Phase 11)
- [ ] Asset label `TC-LT-NNN` attached (underside) – status `Received`
- [ ] Warranty registered with vendor

## B. Firmware

- [ ] BIOS/UEFI updated to latest vendor release
- [ ] Secure Boot **on**, TPM 2.0 **on**, virtualisation (VT-x) **on** (Developer tier)
- [ ] BIOS administrator password set (stored in password manager)
- [ ] Boot order: internal disk first; USB/PXE boot protected by password

## C. Operating system

- [ ] Windows 11 Pro clean install / Autopilot reset (no OEM bloatware)
- [ ] Hostname set to asset tag
- [ ] All Windows Updates and driver pack for the tier installed
- [ ] Joined to `corp.techcorp.example` / enrolled in Entra ID + Intune
- [ ] Computer object moved to the correct OU (`Workstations`)
- [ ] `gpupdate /force` completed, `gpresult /r` shows baseline GPOs

## D. Security

- [ ] BitLocker enabled; `manage-bde -status` shows **Fully Encrypted**, protection on
- [ ] Recovery key visible in AD / Entra ID device object
- [ ] Defender for Business onboarded, real-time protection + tamper protection on
- [ ] Windows LAPS password present for the device
- [ ] User is **not** in the local Administrators group

## E. Software

- [ ] Core image apps installed (M365 Apps, Teams, OneDrive, Edge, Reader, 7-Zip, password manager)
- [ ] Department add-ons installed and licensed
- [ ] OneDrive Known Folder Move active after user sign-in

## F. Handover to user

- [ ] User signs in, sets up MFA and Windows Hello
- [ ] Outlook, Teams, OneDrive and printer tested with the user
- [ ] Dock + both monitors tested at a desk
- [ ] User has signed the Acceptable Use Policy
- [ ] Inventory updated: `AssignedTo`, `Status = Deployed`

**Built by:** ________ · **Verified by user:** ________
