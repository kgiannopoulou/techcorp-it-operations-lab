# File Server TC-FS01: Shares, DFS Namespace, Quotas and Shadow Copies

| Field | Value |
|---|---|
| Document ID | WIN-PRC-006 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved after the first lab build |
| Last reviewed | 2026-11-27 |
| Related requirements | BR-03, BR-09, BR-21, BR-26 |
| Source data | [folders.csv](folders.csv) · [file-permissions.csv](../permissions/file-permissions.csv) |

## Purpose

Give each department a private area and the whole company a shared area on
TC-FS01 (BR-03), behind one path that never changes:
`\\corp.techcorp.example\dfs\…`. Most personal files live in OneDrive
(Phase 5); the file server holds shared department data and legacy files.

## Layout

```text
D:\Shares                       Administrators + SYSTEM only (protected)
├── Company          share Company      → \\corp.techcorp.example\dfs\Company
├── Departments      share Departments  → \\corp.techcorp.example\dfs\Departments   (ABE)
│   ├── Management
│   ├── Finance
│   │   └── Payroll              inheritance broken – payroll staff only
│   ├── HR
│   │   └── Payroll-Inputs       + read for payroll staff
│   ├── Sales
│   ├── Development
│   └── Support
├── Managers         share Managers     → \\corp.techcorp.example\dfs\Managers
└── IT               share IT$          → \\corp.techcorp.example\dfs\IT
D:\DFSRoots\dfs      namespace root share "dfs"
```

| Share | Share permissions | ABE | Offline files |
|---|---|---|---|
| Company, Departments, Managers, IT$ | Administrators: Full · Authenticated Users: Change | On | Manual (default) |
| dfs (namespace root) | Administrators: Full · Authenticated Users: Read | – | – |

Share permissions are deliberately wide: **NTFS decides** (one place to
manage and audit). See [ntfs-and-share-permissions.md](../permissions/ntfs-and-share-permissions.md).

### Design change WIN-CHG-002 – `dfs\IT$` becomes `dfs\IT`

[naming-conventions.md](../../15-documentation/standards/naming-conventions.md#7-file-shares)
listed the IT area as `\\corp.techcorp.example\dfs\IT$`. The `$` suffix only
hides an **SMB share** from share browsing; a folder inside a DFS namespace is
not a share, so a `$` there hides nothing and only makes the path awkward. The
SMB share on TC-FS01 stays `IT$` (hidden when someone browses `\\TC-FS01`),
the namespace folder is `IT`, and what actually keeps people out is NTFS
(`DL_FS_IT_RW` only). Folder names are not secrets – permissions are the control.

## Prerequisites

- [ ] TC-FS01 built with `D:` ([server-build.md](../installation/server-build.md)) and joined to `TechCorp/Computers/Servers`
- [ ] `DL_FS_` groups exist (`Deploy-TechCorpAd.ps1`)
- [ ] Signed in as `adm-eren.yeager`

## Procedure

1. **Roles.**

   ```powershell
   Install-WindowsFeature FS-FileServer, FS-DFS-Namespace, FS-Resource-Manager -IncludeManagementTools
   ```

2. **Folders, NTFS, shares and namespace** – one script, from the CSVs:

   ```powershell
   .\Deploy-TechCorpFileShare.ps1 -WhatIf            # read the planned ACLs
   .\Deploy-TechCorpFileShare.ps1 -CreateNamespace
   ```

   *Expected result:* 12 folders, 4 data shares + `dfs`, namespace
   `\\corp.techcorp.example\dfs` with folders Company, Departments, Managers, IT.

3. **Quotas (FSRM)** – soft limits that warn, so nobody's work is blocked:

   ```powershell
   New-FsrmQuotaTemplate -Name 'TC-Department-50GB-Soft' -Size 50GB -SoftLimit
   'Management','Finance','HR','Sales','Development','Support' | ForEach-Object {
       New-FsrmQuota -Path "D:\Shares\Departments\$_" -Template 'TC-Department-50GB-Soft'
   }
   New-FsrmQuota -Path 'D:\Shares\Company' -Size 20GB -SoftLimit
   ```

   Production adds an e-mail threshold at 85 % once SMTP exists (Phase 5).

4. **File screen** – block executables and scripts from being stored in data shares:

   ```powershell
   New-FsrmFileGroup -Name 'TC-Executables' -IncludePattern @('*.exe','*.msi','*.bat','*.cmd','*.ps1','*.vbs','*.js','*.scr')
   New-FsrmFileScreen -Path 'D:\Shares\Departments' -IncludeGroup 'TC-Executables' -Active
   ```

   The IT share is excluded – it holds installers.

5. **Shadow copies** – twice a day on weekdays, 10 % of the volume:

   ```powershell
   vssadmin add shadowstorage /for=D: /on=D: /maxsize=10%
   $action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -Command `"Invoke-CimMethod -ClassName Win32_ShadowCopy -MethodName Create -Arguments @{ Volume = 'D:\' }`""
   $trigger = @(
       New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday, Tuesday, Wednesday, Thursday, Friday -At 07:00
       New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday, Tuesday, Wednesday, Thursday, Friday -At 12:00
   )
   Register-ScheduledTask -TaskName 'TC-ShadowCopy-D' -Action $action -Trigger $trigger -User 'SYSTEM' -RunLevel Highest
   ```

   Users restore their own files via *Properties → Previous Versions*. Shadow
   copies are **not a backup** (same disk, same server) – backups are Phase 10 (BR-20).

## Verification

From `TC-LT-LAB01`, signed in as different users:

```powershell
Get-ChildItem \\corp.techcorp.example\dfs\Departments   # nile.dok sees only Finance (ABE)
New-Item T:\test.txt; Remove-Item T:\test.txt            # works in own department
Remove-Item \\corp.techcorp.example\dfs\Departments\Finance   # denied - root folder protected
Get-ChildItem \\corp.techcorp.example\dfs\Departments\Finance\Payroll   # nile.dok: Access denied
Get-DfsnFolderTarget -Path \\corp.techcorp.example\dfs\Departments
```

On TC-FS01: `Get-SmbShare | Format-Table Name, Path, FolderEnumerationMode`,
`Get-FsrmQuota`, `vssadmin list shadows /for=D:`. Then
`Test-TechCorpAd.ps1 -FileServer TC-FS01` from the DC – NTFS and Share rows PASS.

## Rollback

`Remove-DfsnFolder`/`Remove-SmbShare` remove access paths without touching
data. ACLs: re-run `Deploy-TechCorpFileShare.ps1` (it converges to the CSV).
Never delete `D:\Shares` folders that contain data.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| User sees an empty `Departments` folder | ABE on, user not in any department group | Group membership (`whoami /groups`) |
| `\\corp.techcorp.example\dfs` not found but `\\TC-FS01\Company` works | Client DNS not the DCs, or DFS client cannot reach a DC for the referral | `dfsutil /pktinfo`; DNS option 6 |
| User can delete files of colleagues | Expected – Modify on the department. Restrict sub-folders if needed | Add a sub-folder row in `folders.csv` |
| Access denied right after being added to a group | Old Kerberos ticket | Log off / on (SC-ACC-002) |
| Save blocked: "access denied" for a `.ps1` in Development | File screen | Developers keep code in Git, not on the file server |

## Evidence

`15-documentation/screenshots/phase-03/`: DFS Management console, share
list with ABE, ABE view as two different users, Previous Versions restore.

## References

- [DFS Namespaces overview](https://learn.microsoft.com/windows-server/storage/dfs-namespaces/dfs-overview)
- [Access-based enumeration](https://learn.microsoft.com/windows-server/storage/dfs-namespaces/enable-access-based-enumeration-on-a-namespace)
- [FSRM quotas and file screens](https://learn.microsoft.com/windows-server/storage/fsrm/fsrm-overview)
