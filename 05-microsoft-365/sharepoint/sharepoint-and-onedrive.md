# SharePoint Sites, Sharing and OneDrive

| Field | Value |
|---|---|
| Document ID | M365-PRC-006 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved after the lab tenant is built |
| Last reviewed | 2026-11-27 |
| Related requirements | BR-03, BR-09, BR-20, BR-26 |
| Source data | [sites.csv](sites.csv) |

## 1. Where files live

| Kind of file | Home | Why |
|---|---|---|
| My working files | **OneDrive** (Desktop/Documents/Pictures via Known Folder Move) | Follows the user to any desk and any laptop (hot-desking, BR-04) |
| Team files | The team's **SharePoint site** (Files tab in Teams) | Co-authoring, versioning, works from home without VPN (BR-09) |
| Published company documents | **Intranet** communication site | Read by everyone, edited by Management/HR |
| Legacy and large shared data, payroll | **TC-FS01** shares (M5) | Stays on-prem until a migration project; payroll keeps its tested NTFS model |

## 2. Sharing model

The tenant setting is the **ceiling**; each site may be stricter, never looser
(CI-checked in `Get-TechCorpM365Plan.ps1 -SelfTest`).

| Level | Meaning | Where |
|---|---|---|
| Tenant: *New and existing guests* (`ExternalUserSharingOnly`) | Guests must sign in; **no "Anyone" links** | Ceiling |
| OneDrive: *Existing guests* | Users can share from OneDrive only with guests IT already invited | All OneDrives |
| Default link | *Specific people*, *View* | Tenant |

| Site | Path | External sharing |
|---|---|---|
| TechCorp | /sites/grp-all | Disabled |
| Management | /sites/grp-management | **Disabled** (BR-26) |
| Finance | /sites/grp-finance | **Disabled** (BR-26) |
| HR | /sites/grp-hr | **Disabled** (BR-26) |
| Sales & Marketing | /sites/grp-sales | New and existing guests (client proposals) |
| Development | /sites/grp-development | Existing guests only |
| Customer Support | /sites/grp-support | Existing guests only |
| Intranet | /sites/intranet | Disabled |

## 3. Procedure

1. Team sites are created by the teams (M365-PRC-005). Then:

   ```powershell
   Connect-SPOService -Url https://<tenant>-admin.sharepoint.com      # Windows PowerShell 5.1
   .\07-powershell\microsoft-365\Deploy-TechCorpM365.ps1 -Skip Users,Licensing,Mail,Teams `
       -AdDomainGuid (Get-ADDomain).ObjectGUID
   ```

   This sets the tenant ceiling and default links, restricts **OneDrive sync
   to domain-joined PCs** (personal computers can use the browser, not sync
   company data), creates the intranet site and applies each site's sharing level.

2. **Intranet permissions** (*Site settings → Site permissions*): owners
   hange.zoe, historia.reiss; visitors *Everyone except external users*.
3. **Versioning**: default (automatic version limits) – no change.
4. **OneDrive Known Folder Move**: `C-Workstations-OneDrive` GPO –
   `Deploy-TechCorpGpo.ps1 -TenantId <tenant-guid>` writes the tenant ID into
   `KFMSilentOptIn`. Users see a notification that Desktop/Documents/Pictures
   are now backed up; they cannot move them back.
5. **OneDrive storage and retention**: 1 TB per user (default); deleted users'
   OneDrive kept **90 days** (*SharePoint admin center → Settings → OneDrive retention*) – longer than the 30-day leaver window.

## 4. Verification

| Test | Expected |
|---|---|
| `Test-TechCorpM365.ps1` SharePoint rows | PASS |
| Share a file from the HR site to a Gmail address | Option not offered |
| Share from Sales to a client address | Guest invitation (sign-in required), no "Anyone" link option |
| OneDrive on a lab non-domain PC | Sync refused; browser works |
| New laptop, first sign-in | Desktop/Documents show the OneDrive "cloud" status icons |

## 5. Not yet

- Sensitivity labels and DLP for HR/Finance (Purview, included in BP) – Phase 9.
- Backup of M365 data (BR-20 – Microsoft's retention is not a backup) – Phase 10.
- Migrating the Company share to the intranet – a project after go-live.
