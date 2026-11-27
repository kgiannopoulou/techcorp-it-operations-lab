# Deploy Active Directory Domain Services (forest, second DC, sites, FSMO)

| Field | Value |
|---|---|
| Document ID | WIN-PRC-002 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved after the first lab build |
| Last reviewed | 2026-11-27 |
| Related requirements | BR-01, BR-14, BR-19, BR-32 |

## Purpose

Create the `corp.techcorp.example` forest on TC-DC01, add TC-DC02 as a second
domain controller so that logons and DNS survive the loss of one DC, and
apply the domain-wide settings every later procedure depends on.

## Design decisions

| Decision | Value | Why |
|---|---|---|
| Forest / domain | One forest, one domain `corp.techcorp.example`, NetBIOS `TECHCORP` | 20 users, one office – anything more is complexity without benefit ([naming-conventions.md](../../15-documentation/standards/naming-conventions.md)) |
| Functional level | Windows Server 2025 (`Win2025`) | Both DCs are 2025; enables the newest Kerberos/LDAP security features |
| DCs | TC-DC01 + TC-DC02, both DNS servers and global catalogs | A single DC is a single point of failure for every logon (BR-19) |
| FSMO roles | All five on TC-DC01 | Small single-site domain – one place to look; DC02 can seize them if DC01 is lost |
| Time | PDC emulator (TC-DC01) syncs from TC-FW01 NTP; everything else follows the domain hierarchy | Kerberos fails with more than 5 minutes of clock skew |
| Site | `Athens-HQ` with all internal subnets | Clients find the nearest DC and correct site-aware services |
| Recycle Bin | Enabled | Restores a deleted user with group memberships intact (scenario SC-ACC-004) |
| Built-in Administrator | Kept as the **break-glass** account, long random password in a sealed envelope + password manager; never used day to day | Daily admin is done with `adm-eren.yeager` (see [user-accounts.md](../users-and-groups/user-accounts.md)) |

## Prerequisites

- [ ] TC-DC01 and TC-DC02 built and patched – [server-build.md](../installation/server-build.md)
- [ ] TC-FW01 NTP service listening on the SERVERS interface (*Services → NTP → Interfaces*)
- [ ] DSRM password generated and stored in the password manager

## Procedure

### Part A – create the forest on TC-DC01

1. **Install the role.**

   ```powershell
   Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
   ```

2. **Promote to the first DC of a new forest.** DNS is installed with it.

   ```powershell
   Install-ADDSForest -DomainName 'corp.techcorp.example' -DomainNetbiosName 'TECHCORP' `
       -ForestMode Win2025 -DomainMode Win2025 -InstallDns `
       -SafeModeAdministratorPassword (Read-Host -AsSecureString 'DSRM password') -Force
   ```

   *Expected result:* the server reboots; you sign in as `TECHCORP\Administrator`.

3. **Check the domain is healthy before going any further.**

   ```powershell
   Get-ADDomain | Select-Object DNSRoot, NetBIOSName, DomainMode, PDCEmulator
   dcdiag /q                                   # no output = no errors
   Resolve-DnsName _ldap._tcp.dc._msdcs.corp.techcorp.example -Type SRV
   ```

4. **Rename the site and register the subnets.**

   ```powershell
   Get-ADReplicationSite 'Default-First-Site-Name' | Rename-ADObject -NewName 'Athens-HQ'
   '10.10.10.0/24','10.10.20.0/24','10.10.30.0/24','10.10.40.0/24','10.10.60.0/24' |
       ForEach-Object { New-ADReplicationSubnet -Name $_ -Site 'Athens-HQ' }
   ```

   The guest subnet (VLAN 50) is deliberately **not** registered – guests are
   never domain clients.

5. **Make the PDC emulator the authoritative time source.**

   ```powershell
   w32tm /config /manualpeerlist:"10.10.30.1,0x8" /syncfromflags:manual /reliable:yes /update
   Restart-Service w32time
   w32tm /resync /force
   w32tm /query /status                        # Source: 10.10.30.1
   ```

6. **Enable the AD Recycle Bin** (cannot be disabled afterwards – intended).

   ```powershell
   Enable-ADOptionalFeature 'Recycle Bin Feature' -Scope ForestOrConfigurationSet `
       -Target 'corp.techcorp.example' -Confirm:$false
   ```

7. **Send new computer accounts to a managed OU** (after Part C has created the OUs):

   ```powershell
   redircmp "OU=Standard,OU=Workstations,OU=Computers,OU=TechCorp,DC=corp,DC=techcorp,DC=example"
   ```

   Otherwise joined computers land in the `CN=Computers` container, where no
   GPO can be linked.

### Part B – add TC-DC02 (Server Core)

1. **Point DC02 at DC01 for DNS**, then install the role:

   ```powershell
   Set-DnsClientServerAddress -InterfaceAlias (Get-NetAdapter).Name -ServerAddresses 10.10.30.11
   Install-WindowsFeature AD-Domain-Services
   ```

2. **Promote as an additional DC** (it does not need to be joined first):

   ```powershell
   Install-ADDSDomainController -DomainName 'corp.techcorp.example' -InstallDns -SiteName 'Athens-HQ' `
       -Credential (Get-Credential 'TECHCORP\Administrator') `
       -SafeModeAdministratorPassword (Read-Host -AsSecureString 'DSRM password') -Force
   ```

3. **Set the DNS client order on both DCs** – partner first, itself second
   (avoids a DC being an "island" that only asks itself after a restart):

   | DC | Preferred DNS | Alternate DNS |
   |---|---|---|
   | TC-DC01 | 10.10.30.12 | 127.0.0.1 |
   | TC-DC02 | 10.10.30.11 | 127.0.0.1 |

4. **Verify replication.**

   ```powershell
   repadmin /replsummary                         # 0 fails, largest delta minutes
   repadmin /showrepl TC-DC02
   Get-ADReplicationFailure -Target 'corp.techcorp.example' -Scope Domain
   dcdiag /s:TC-DC02 /q
   netdom query fsmo                             # all five on TC-DC01
   ```

   Test it: create a test OU on DC01, run `repadmin /syncall /AdeP`, confirm it
   appears with `Get-ADOrganizationalUnit -Server TC-DC02 -Filter 'Name -eq "ReplTest"'`, delete it.

### Part C – TechCorp objects

Run the scripts in [07-powershell/active-directory](../../07-powershell/active-directory/)
on TC-DC01 as `TECHCORP\Administrator` **once** (to create the admin accounts),
then as `adm-eren.yeager` for everything after:

| # | Script | Creates |
|---|---|---|
| 1 | `Get-TechCorpAdPlan.ps1 -SelfTest` | Nothing – validates the CSVs first |
| 2 | `Deploy-TechCorpAd.ps1 -WhatIf`, then without `-WhatIf` | OUs, groups, 20 users, `adm-`/`wadm-` accounts, memberships, delegation, PSO, machine quota 0 |
| 3 | `Deploy-TechCorpGpo.ps1 -PrepareLaps` | GPOs, links, filtering, registry settings, LAPS schema + permissions |
| 4 | `Deploy-TechCorpFileShare.ps1 -CreateNamespace` (on TC-FS01, after joining it) | Folders, NTFS, shares, DFS namespace |
| 5 | `Test-TechCorpAd.ps1 -FileServer TC-FS01 -OutputPath …` | Nothing – evidence CSV |

Join TC-FS01 between steps 3 and 4:

```powershell
Set-DnsClientServerAddress -InterfaceAlias (Get-NetAdapter).Name -ServerAddresses 10.10.30.11, 10.10.30.12
Add-Computer -DomainName 'corp.techcorp.example' -OUPath 'OU=Servers,OU=Computers,OU=TechCorp,DC=corp,DC=techcorp,DC=example' `
    -Credential 'TECHCORP\adm-eren.yeager' -Restart
```

## Snapshots and domain controllers

Restoring a VM snapshot of a DC rolls its database back in time while its
partner remembers the newer changes (**USN rollback**): replication silently
stops for that DC. Hyper-V protects against this with VM-Generation ID;
do not rely on VirtualBox doing the same. Rules for the lab:

- Snapshot DCs only **before** promotion, or snapshot **both DCs while both are shut down** and only ever restore them together.
- To practise recovery, use AD backup/restore (Phase 10), not snapshots.

## Verification

| Check | Command | Expected |
|---|---|---|
| DC health | `dcdiag /e /q` | No errors |
| Replication | `repadmin /replsummary` | 0 failures on both DCs |
| FSMO | `netdom query fsmo` | TC-DC01 for all five roles |
| Time | `w32tm /monitor` | Both DCs within 1 s of each other; PDC source 10.10.30.1 |
| Recycle Bin | `Get-ADOptionalFeature 'Recycle Bin Feature'` | `EnabledScopes` not empty |
| Whole domain vs plan | `Test-TechCorpAd.ps1` | No FAIL |

## Rollback

- Before Part C: demote with `Uninstall-ADDSDomainController` (DC02) or rebuild
  from the `01-base-os` snapshot (both DCs, nothing else joined yet).
- **If TC-DC01 is lost for good:** seize the roles on DC02 –
  `Move-ADDirectoryServerOperationMasterRole -Identity TC-DC02 -OperationMasterRole 0,1,2,3,4 -Force`,
  clean up DC01's metadata (*ADUC → delete the computer object*), make DC02 the
  NTP-reliable PDC (step A5), build a new DC.

## Troubleshooting

See [ad-troubleshooting.md](ad-troubleshooting.md).

## Evidence

`15-documentation/screenshots/phase-02/`: `dcdiag /q`, `repadmin /replsummary`,
`netdom query fsmo`, `w32tm /query /status`, Sites and Services with the subnets.

## References

- [Install AD DS by using PowerShell](https://learn.microsoft.com/windows-server/identity/ad-ds/deploy/install-active-directory-domain-services--level-100-)
- [Active Directory Recycle Bin](https://learn.microsoft.com/windows-server/identity/ad-ds/get-started/adac/introduction-to-active-directory-administrative-center-enhancements--level-100-)
- [USN rollback](https://learn.microsoft.com/troubleshoot/windows-server/active-directory/detect-and-recover-from-usn-rollback)
