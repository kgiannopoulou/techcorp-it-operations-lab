# Build a TechCorp Laptop (Windows 11, Domain Join, Baseline)

| Field | Value |
|---|---|
| Document ID | END-PRC-001 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved after the first lab build |
| Last reviewed | 2026-11-27 |
| Related requirements | BR-01, BR-04, BR-10, BR-12, BR-14 |

## Purpose

Turn a new (or returned) laptop into a verified TechCorp workstation in about
90 minutes, following the [workstation standard](../../01-office-deployment/workstation-deployment/workstation-standard.md).
The paper trail is the [build checklist](../../01-office-deployment/workstation-deployment/workstation-build-checklist.md);
this document is the *how*.

## Prerequisites

- [ ] Laptop has an asset tag and a row in `hardware-inventory.csv` (Hostname = asset tag)
- [ ] Windows 11 USB installer (Media Creation Tool, current release) – IT store cupboard
- [ ] USB stick with a copy of this repository (or network access to `\\corp.techcorp.example\dfs\IT`) and the Office Deployment Tool `setup.exe`
- [ ] `wadm-eren.yeager` credentials (domain join is delegated to `GG_IT_WorkstationAdmins`; standard users cannot join – quota 0)
- [ ] Desk port on VLAN 20 (STAFF); DHCP option 6 already points at the DCs

### Lab equivalent – `TC-LT-LAB01`

```powershell
$vbox = "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe"
$vm = 'TC-LT-LAB01'
& $vbox createvm --name $vm --ostype Windows11_64 --register
& $vbox modifyvm $vm --memory 4096 --cpus 2 --firmware efi --tpm-type 2.0 `
    --nic1 intnet --intnet1 tc-vlan20 --nictype1 82540EM
& $vbox modifynvram $vm inituefivarstore
& $vbox modifynvram $vm enrollmssignatures
& $vbox modifynvram $vm enrollorclpk                    # Secure Boot on
& $vbox createmedium disk --filename "$HOME\VirtualBox VMs\$vm\$vm.vdi" --size 81920
& $vbox storagectl $vm --name SATA --add sata --controller IntelAhci
& $vbox storageattach $vm --storagectl SATA --port 0 --device 0 --type hdd --medium "$HOME\VirtualBox VMs\$vm\$vm.vdi"
& $vbox storageattach $vm --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$HOME\Downloads\Win11_Enterprise_Eval.iso"
```

The VM uses Windows 11 **Enterprise Evaluation** (90 days) instead of Pro –
same domain-join, BitLocker and GPO behaviour. Hostname `TC-LT-LAB01` is not
in the inventory, so the first `Test-TechCorpEndpoint.ps1` row will FAIL in
the lab – expected; everything else must pass. VirtualBox 7 provides a
virtual TPM 2.0 and Secure Boot, so BitLocker works.

## Procedure

1. **Firmware** (per model, once per laptop): update BIOS, Secure Boot **on**,
   TPM **on**, VT-x **on** (all tiers – Hyper-V-based security features need it),
   BIOS admin password from the password manager.

2. **Clean install.** Boot from USB, delete all partitions, install
   *Windows 11 Pro*. In OOBE: region Greece, keyboard **US + Greek**; on
   *"How would you like to set up this device?"* choose **Set up for work or
   school → Sign-in options → Domain join instead**, create the temporary
   local account `tcsetup` with a random password (deleted in step 8).

3. **Rename and join** (elevated PowerShell as `tcsetup`):

   ```powershell
   $tag  = 'TC-LT-014'                         # asset tag = hostname
   $tier = 'Developer'                         # from employees.csv DeviceTier of the owner
   $ou   = "OU=$tier,OU=Workstations,OU=Computers,OU=TechCorp,DC=corp,DC=techcorp,DC=example"
   if ($tier -eq 'Creative') { $ou = $ou -replace 'OU=Creative', 'OU=Standard' }
   Add-Computer -DomainName corp.techcorp.example -NewName $tag -OUPath $ou `
       -Credential TECHCORP\wadm-eren.yeager -Restart
   ```

   *Expected result:* reboot; the computer object exists in the tier OU
   (`Get-ADComputer TC-LT-014` from the IT laptop).

4. **Policy.** Sign in as `wadm-eren.yeager` (allowed on workstations), then:

   ```powershell
   gpupdate /force
   gpresult /r /scope computer      # C-AllComputers-*, C-Workstations-* listed
   net localgroup Administrators    # Administrator + TECHCORP\GG_IT_WorkstationAdmins only
   ```

5. **BitLocker** – recovery password first (escrowed to AD by policy), then TPM:

   ```powershell
   Add-BitLockerKeyProtector -MountPoint C: -RecoveryPasswordProtector
   $rp = (Get-BitLockerVolume C:).KeyProtector | Where-Object KeyProtectorType -eq 'RecoveryPassword'
   Backup-BitLockerKeyProtector -MountPoint C: -KeyProtectorId $rp.KeyProtectorId
   Enable-BitLocker -MountPoint C: -EncryptionMethod XtsAes256 -TpmProtector -UsedSpaceOnly
   ```

   Check the key is in AD before handing over:
   `Get-ADObject -SearchBase (Get-ADComputer TC-LT-014).DistinguishedName -Filter 'objectClass -eq "msFVE-RecoveryInformation"'`.
   After hybrid join (step 7) also run `BackupToAAD-BitLockerKeyProtector -MountPoint C: -KeyProtectorId $rp.KeyProtectorId`.

6. **Software baseline** for the owner:

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\07-powershell\endpoint\Install-TechCorpBaseline.ps1 -Username armin.arlert -ListOnly
   .\07-powershell\endpoint\Install-TechCorpBaseline.ps1 -Username armin.arlert -OdtPath D:\ODT
   ```

   Then the `manual` items it lists (vendor utility, password manager,
   department apps). Developer tier: restart after WSL.

7. **Hybrid join.** Happens automatically: the computer object is in a synced
   OU, Entra Connect exports it (≤ 30 min), the device registers at the next
   sign-in / scheduled task. Check with `dsregcmd /status` → `AzureAdJoined : YES`,
   `DomainJoined : YES`. Force: `dsregcmd /join` as SYSTEM, or reboot.

8. **Clean up and verify.**

   ```powershell
   Remove-LocalUser tcsetup
   .\07-powershell\endpoint\Test-TechCorpEndpoint.ps1 -Username armin.arlert -OutputPath "C:\ProgramData\TechCorp\Logs\$env:COMPUTERNAME-build.csv"
   ```

   All rows PASS (PRT row: re-run in the user's session at handover).

9. **Handover** – section F of the build checklist: user signs in with their
   one-time password, sets their own, registers MFA (Microsoft Authenticator)
   and Windows Hello, Outlook/Teams/OneDrive open without extra prompts
   (single sign-on via PRT), default printer works, AUP signed. Update the
   inventory row `Status = Deployed`.

## Verification

`Test-TechCorpEndpoint.ps1` all PASS, attached to the build ticket; computer
object in the right OU; device visible in Entra admin center → *Devices* with
join type *Microsoft Entra hybrid joined*.

## Rollback

Not a production change – a failed build is rebuilt from step 2. Before
reusing a laptop for another person: `Remove-Computer`, delete the AD computer
object and the Entra device, clear the TPM, clean install.

## Troubleshooting

See [endpoint-troubleshooting.md](../troubleshooting/endpoint-troubleshooting.md)
and scenarios SC-WIN-001 (join fails – DNS), SC-WIN-004 (not hybrid joined),
SC-HW-001 (BitLocker recovery after BIOS update).

## Evidence

`15-documentation/screenshots/phase-04/`: `dsregcmd /status` (sanitised IDs),
`manage-bde -status`, `Test-TechCorpEndpoint` CSV, Entra device list.
