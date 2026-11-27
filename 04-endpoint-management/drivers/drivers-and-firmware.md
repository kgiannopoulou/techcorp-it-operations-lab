# Drivers and Firmware

| Field | Value |
|---|---|
| Document ID | END-PRC-003 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved after the first production laptop |
| Last reviewed | 2026-11-27 |
| Related requirements | BR-04, BR-12, BR-16 |

## Principles

- **One model per tier** ([workstation standard §1](../../01-office-deployment/workstation-deployment/workstation-standard.md#1-hardware-tiers)) → one driver set per tier.
- Drivers come from **Windows Update first**; the vendor's update utility fills the gaps (dock firmware, BIOS, Thunderbolt). No driver packs downloaded from random sites.
- Firmware is updated at build time and then **quarterly** (maintenance calendar, Phase 11), or immediately for a security advisory.
- **BitLocker is suspended before every BIOS/UEFI update** – otherwise the TPM measurements change and the laptop asks for its 48-digit recovery key (SC-HW-001).

## Driver sources per tier

| Tier | Model (one per tier) | Driver source | Notes |
|---|---|---|---|
| Standard / Creative | Business 14″/16″ line of the chosen vendor | Windows Update + vendor utility | Creative: GPU driver from the vendor utility (ISV-certified) |
| Developer / IT | Business 14″ performance line | Windows Update + vendor utility | Virtualisation on in firmware |
| Dock | USB-C/Thunderbolt dock | Vendor dock firmware tool | Firmware decides DisplayPort MST / dual-monitor support (SC-HW-002) |

Record the model and its driver/BIOS baseline in the asset register
(Phase 11). In the lab the VM uses inbox drivers only.

## Procedure – BIOS / firmware update

1. Laptop on AC power, docked or charger connected.
2. Suspend BitLocker for one reboot:

   ```powershell
   Suspend-BitLocker -MountPoint C: -RebootCount 1
   ```

3. Run the vendor utility (or the vendor's BIOS capsule via Windows Update).
4. After reboot: `Get-BitLockerVolume C:` → `ProtectionStatus : On` (resumes automatically).
5. `Test-TechCorpEndpoint.ps1` – Secure Boot and TPM rows still PASS.

## Procedure – driver problem

1. *Device Manager* → device with a warning → *Properties → Events* (driver install history).
2. `pnputil /enum-drivers` and `Get-WinEvent -LogName 'Microsoft-Windows-Kernel-PnP/Configuration' -MaxEvents 20`.
3. Roll back if it started after an update: *Driver → Roll Back Driver*.
4. Pause the bad driver for the fleet: note in the ticket; in M7 a driver update policy in Intune can hold it.

## Rollback

BIOS updates generally cannot be downgraded (vendor policy and security
fuses) – this is why the BitLocker step matters. Drivers: *Roll Back
Driver* or `pnputil /delete-driver <oemNN.inf> /uninstall`.
