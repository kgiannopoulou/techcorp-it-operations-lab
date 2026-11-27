# Build the Windows Server VMs (TC-DC01, TC-DC02, TC-FS01)

| Field | Value |
|---|---|
| Document ID | WIN-PRC-001 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved after the first lab build |
| Last reviewed | 2026-11-27 |
| Related requirements | BR-01, BR-19, BR-32 |

## Purpose

Build the three Windows Server 2025 virtual machines that run TechCorp's
identity and file services, with the static addresses from the
[IP addressing plan](../../02-network-infrastructure/ip-addressing/ip-addressing-plan.md).

## Scope

| VM | Role | Edition / install option | IP (VLAN 30) | Production host | Lab host |
|---|---|---|---|---|---|
| TC-DC01 | AD DS, DNS, all FSMO roles, PDC time source | Standard, **Desktop Experience** | 10.10.30.11 | Hyper-V on TC-HV01 | VirtualBox |
| TC-DC02 | AD DS, DNS, global catalog | Standard, **Server Core** | 10.10.30.12 | Hyper-V on TC-HV01 | VirtualBox |
| TC-FS01 | File server, DFS Namespace, FSRM | Standard, **Server Core** | 10.10.30.20 | Hyper-V on TC-HV01 | VirtualBox |

Why Server Core for DC02 and FS01: smaller attack surface, fewer updates and
reboots, less RAM. DC01 keeps the desktop so that the lab has GPMC, ADUC and
DNS Manager on a server; in production all management is done from the IT
laptop with RSAT, and DC01 would be Core as well.

## Prerequisites

- [ ] Milestone 4 lab built: `TC-FW01-LAB` running with the `tc-vlan30` internal network ([lab-environment.md](../../02-network-infrastructure/topology/lab-environment.md))
- [ ] Windows Server 2025 **Evaluation** ISO downloaded from the Microsoft Evaluation Center (180 days, free)
- [ ] Host RAM checked – see the budget below
- [ ] A password manager entry ready for the local Administrator and DSRM passwords (never stored in this repository)

### Lab RAM budget

| VM | RAM | Needed for |
|---|---:|---|
| TC-FW01-LAB (pfSense) | 1 GB | Always |
| TC-DC01 | 3 GB | Always |
| TC-DC02 | 2 GB | Replication, FSMO and DC-failure exercises |
| TC-FS01 | 2 GB | File services and permissions |
| TC-LT-LAB01 (Windows 11) | 4 GB | Domain join, GPO and access tests |
| **Total** | **12 GB** | **16 GB host recommended** |

On an 8 GB host: give the client 3 GB and start TC-DC02 only for the
sessions that need it.

## Procedure

1. **Create the three VMs** (PowerShell on the lab PC; adjust `$iso`).

   ```powershell
   $vbox = "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe"
   $iso  = "$HOME\Downloads\WindowsServer2025_Eval.iso"
   $vms  = @(
       @{ Name = 'TC-DC01'; Ram = 3072; Data = 0 }
       @{ Name = 'TC-DC02'; Ram = 2048; Data = 0 }
       @{ Name = 'TC-FS01'; Ram = 2048; Data = 51200 }   # 50 GB data disk (production: 1 TB)
   )
   foreach ($v in $vms) {
       $dir = "$HOME\VirtualBox VMs\$($v.Name)"
       & $vbox createvm --name $v.Name --ostype Windows2022_64 --register   # use Windows2025_64 if 'VBoxManage list ostypes' shows it
       & $vbox modifyvm $v.Name --memory $v.Ram --cpus 2 --firmware efi `
           --nic1 intnet --intnet1 tc-vlan30 --nictype1 82540EM --clipboard-mode disabled
       & $vbox storagectl $v.Name --name SATA --add sata --controller IntelAhci
       & $vbox createmedium disk --filename "$dir\$($v.Name).vdi" --size 61440
       & $vbox storageattach $v.Name --storagectl SATA --port 0 --device 0 --type hdd --medium "$dir\$($v.Name).vdi"
       if ($v.Data) {
           & $vbox createmedium disk --filename "$dir\$($v.Name)-data.vdi" --size $v.Data
           & $vbox storageattach $v.Name --storagectl SATA --port 1 --device 0 --type hdd --medium "$dir\$($v.Name)-data.vdi"
       }
       & $vbox storageattach $v.Name --storagectl SATA --port 2 --device 0 --type dvddrive --medium $iso
   }
   # Domain controllers keep their own time (w32time) - never take it from the host
   foreach ($dc in 'TC-DC01', 'TC-DC02') {
       & $vbox setextradata $dc 'VBoxInternal/Devices/VMMDev/0/Config/GetHostTimeDisabled' 1
   }
   ```

   *Expected result:* three VMs in VirtualBox, each with one NIC on `tc-vlan30`.

2. **Install Windows Server.** Start each VM, choose *Windows Server 2025
   Standard Evaluation* – **(Desktop Experience)** for TC-DC01, the plain
   (Core) image for TC-DC02 and TC-FS01. Set a long, unique local
   Administrator password and record it in the password manager.

3. **Base configuration** (on each server; Core: choose `15` in *sconfig* to
   get PowerShell). Values for TC-DC01 shown – use the table above for the others.

   ```powershell
   $nic = (Get-NetAdapter | Where-Object Status -eq 'Up').Name
   New-NetIPAddress -InterfaceAlias $nic -IPAddress 10.10.30.11 -PrefixLength 24 -DefaultGateway 10.10.30.1
   # Before AD exists, DNS = the firewall resolver. Changed during promotion (WIN-PRC-002).
   Set-DnsClientServerAddress -InterfaceAlias $nic -ServerAddresses 10.10.30.1
   Set-TimeZone -Id 'GTB Standard Time'          # Athens
   Rename-Computer -NewName TC-DC01 -Restart
   ```

   *Expected result:* `ping 10.10.30.1` and `Resolve-DnsName www.microsoft.com` work
   (SERVERS firewall rules 1 and 4).

4. **Patch.** `sconfig` → *6 Install updates* → *All quality updates*; reboot
   until none are left.

5. **Data disk on TC-FS01 only.**

   ```powershell
   Get-Disk | Where-Object PartitionStyle -eq 'RAW' |
       Initialize-Disk -PartitionStyle GPT -PassThru |
       New-Partition -DriveLetter D -UseMaximumSize |
       Format-Volume -FileSystem NTFS -NewFileSystemLabel 'Data' -AllocationUnitSize 65536 -Confirm:$false
   ```

   *Expected result:* `D:` labelled *Data*. NTFS (not ReFS) because FSRM
   quotas, file screens and shadow copies are all used.

6. **Snapshot** every VM: `VBoxManage snapshot TC-DC01 take "01-base-os"`.

   > Snapshots of a domain controller are for *this* step only. Never restore a
   > DC snapshot once the domain exists – see the warning in
   > [ad-ds-deployment.md](../active-directory/ad-ds-deployment.md#snapshots-and-domain-controllers).

## Verification

| Check | Command | Expected |
|---|---|---|
| Name and IP | `hostname; Get-NetIPConfiguration` | Hostname and address as in the table |
| Gateway / internet | `Test-NetConnection 1.1.1.1 -Port 443` | `TcpTestSucceeded : True` |
| Evaluation licence | `slmgr /dlv` | *Timebased activation expiration* ~180 days |
| Time zone | `Get-TimeZone` | (UTC+02:00) Athens, Bucharest |

## Rollback

Delete the VM (`VBoxManage unregistervm <name> --delete`) and rebuild – nothing
depends on it until AD DS is promoted.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| No network adapter in Windows | NIC type not supported | Use `--nictype1 82540EM` (Intel PRO/1000) or install Guest Additions for virtio |
| Gets 169.254.x.x | Static IP not set, or VM on the wrong internal network | `VBoxManage showvminfo <vm>` → NIC 1 = `tc-vlan30` |
| Can ping the gateway, no internet | SERVERS rules missing, or WAN down | Firewall rules SERVERS #4 and NAT ([firewall-rules.md](../../02-network-infrastructure/firewall/firewall-rules.md)) |
| Boot loops to "Press any key" | ISO still first boot device after install | Detach the ISO |

## Evidence

Save to `15-documentation/screenshots/phase-02/` once performed: VirtualBox
VM list, `Get-NetIPConfiguration` of each server, `slmgr /dlv`.

## References

- [Windows Server 2025 Evaluation Center](https://www.microsoft.com/evalcenter/evaluate-windows-server-2025)
- [Server Core vs Desktop Experience](https://learn.microsoft.com/windows-server/get-started/install-options-server-core-desktop-experience)
- [VBoxManage reference](https://www.virtualbox.org/manual/ch08.html)
