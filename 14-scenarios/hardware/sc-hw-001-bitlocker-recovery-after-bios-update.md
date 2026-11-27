# SC-HW-001: Laptop asks for a 48-digit key after an update

| Field | Value |
|---|---|
| Scenario ID | SC-HW-001 |
| Category | Hardware |
| Difficulty | ⭐⭐ |
| Priority (if real) | P2 – user cannot work at all |
| Status | Designed – expected investigation written; **not yet performed in the lab** (evidence pending) |
| Lab | VirtualBox: TC-LT-LAB01 (vTPM, BitLocker on), TC-DC01 |

## 1. The report

> *"My laptop restarted for an update and now shows a blue screen asking for a BitLocker recovery key. I don't have one!"* – Jean Kirstein, Sales & Marketing Manager (phone, 08:40)

## 2. Environment / context

The vendor utility installed a BIOS update overnight. BitLocker was not suspended.

## 3. How the fault is introduced (lab only)

<details>
<summary>Spoiler – fault injected</summary>

With the VM off: `VBoxManage modifyvm TC-LT-LAB01 --tpm-type none`, boot once (recovery screen), then set it back to `2.0` – the TPM's sealed key no longer matches; or toggle Secure Boot keys.

</details>

## 4. Expected investigation

| # | What to check | Command / tool | Expected finding | Conclusion |
|---|---|---|---|---|
| 1 | Recovery screen | Note the **Recovery key ID** (first 8 characters) | e.g. `1A2B3C4D` | Identifies the right key |
| 2 | Find the key (IT laptop, `wadm-`) | ADUC → TC-LT-008 → *BitLocker Recovery* tab, or `Get-ADObject -SearchBase (Get-ADComputer TC-LT-008).DistinguishedName -Filter 'objectClass -eq "msFVE-RecoveryInformation"' -Properties msFVE-RecoveryPassword` | Entry whose name contains the key ID | Escrow worked (C-Workstations-BitLocker) |
| 3 | Alternative | Entra admin center → Devices → TC-LT-008 → *BitLocker keys* | Same key | Second escrow from build step 5 |
| 4 | Verify the caller | Call back on the number in the directory before reading out the key | – | Recovery keys are a security control |
| 5 | Why | Vendor utility log / *Reliability Monitor* | BIOS updated 02:10 | TPM PCR values changed |

## 5. Root cause

A firmware update changed the measurements the TPM uses to release the
BitLocker key; with protection not suspended, Windows falls back to the
recovery password.

## 6. Resolution

1. Read the 48-digit key to the user; laptop boots.
2. BitLocker re-seals to the TPM automatically on the next boot. Check `manage-bde -protectors -get C:`.
3. Because the key was disclosed, **rotate it**: `manage-bde -protectors -delete C: -type RecoveryPassword`, add a new one and back it up (laptop-build step 5).

## 7. Verification

Reboot twice without a prompt; `Test-TechCorpEndpoint.ps1` BitLocker rows PASS; new key in AD and Entra.

## 8. Prevention

- Firmware updates only with `Suspend-BitLocker -RebootCount 1` ([drivers-and-firmware.md](../../04-endpoint-management/drivers/drivers-and-firmware.md)).
- Vendor utility set to *notify*, not auto-install BIOS; M7: Intune updates firmware with BitLocker suspension built in.

## 9. Skills practised

- BitLocker key escrow and recovery, TPM measured boot
- Verifying identity before releasing a secret

## 10. Related

- [laptop-build.md](../../04-endpoint-management/windows-11/laptop-build.md)
