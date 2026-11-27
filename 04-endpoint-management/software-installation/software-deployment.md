# Software Deployment (winget, Office Deployment Tool, RSAT)

| Field | Value |
|---|---|
| Document ID | END-PRC-002 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved after the first lab build |
| Last reviewed | 2026-11-27 |
| Related requirements | BR-01, BR-08, BR-27 |
| Source data | [app-catalogue.csv](app-catalogue.csv) · [m365-apps-configuration.xml](m365-apps-configuration.xml) |

## Purpose

Install exactly the [software baseline](../../01-office-deployment/equipment-inventory/software-baseline.md)
on every laptop, chosen by the owner's department and device tier, with one
script and no clicking through installers.

## How the catalogue works

Each row of `app-catalogue.csv` has a **Target**:

| Target | Who gets it | Example |
|---|---|---|
| `All` | Every laptop (8 core apps) | Microsoft 365 Apps, Teams, Reader, 7-Zip |
| `Department:<Code>` | Owner's department ([department codes](../../15-documentation/standards/naming-conventions.md#4-groups)) | Accounting client → Finance |
| `Tier:<DeviceTier>` | Owner's `DeviceTier` in employees.csv | Docker, WSL, Git → Developer; RSAT → IT |

…and a **Method**: `winget` (package ID), `odt` (Microsoft 365 Apps),
`capability` (RSAT), `feature` (WSL), `builtin` (ships with Windows) or
`manual` (vendor portal – reported as a to-do).

`Install-TechCorpBaseline.ps1 -SelfTest` runs in CI and fails if a row has a
bad ID or target, if any employee would miss a core app, if a developer would
miss Docker/WSL/Git, or if anyone outside IT would get admin tools.

| Employee | Tier | Apps |
|---|---|---:|
| Standard user (e.g. nile.dok, Finance) | Standard | 9 (8 core + accounting client) |
| pieck.finger (Sales) | Creative | 9 (8 core + Creative Cloud) |
| armin.arlert (Development) | Developer | 13 |
| eren.yeager (IT) | IT | 15 |

## Microsoft 365 Apps

[m365-apps-configuration.xml](m365-apps-configuration.xml): 64-bit,
**Monthly Enterprise Channel** (one predictable update per month instead of
several), `O365BusinessRetail`, English + Greek with Greek proofing,
OneDrive/Skype for Business (Lync)/Bing excluded – OneDrive ships with
Windows, Teams is installed separately. Old MSI Office removed. Default save
formats forced to Office Open XML.

```powershell
# download once to the IT share
Invoke-WebRequest https://officecdn.microsoft.com/pr/wsus/setup.exe -OutFile D:\ODT\setup.exe
D:\ODT\setup.exe /configure .\04-endpoint-management\software-installation\m365-apps-configuration.xml
```

Activation happens when the user signs in (licence from
`LIC_M365_BusinessPremium`, SSO through the PRT – no prompts on a hybrid-joined laptop).

## Procedure

1. Elevated PowerShell as `wadm-eren.yeager` (or the LAPS Administrator).
2. `.\Install-TechCorpBaseline.ps1 -Username <owner> -ListOnly` – review.
3. `.\Install-TechCorpBaseline.ps1 -Username <owner> -OdtPath <folder with setup.exe>`.
   Spare laptop: `-Department Sales -Tier Standard`.
4. Complete the `TODO manual` rows.
5. Log: `C:\ProgramData\TechCorp\Logs\baseline-*.csv` (attach to the build ticket).

Re-running is safe – installed apps are reported `present`.

## Adding or removing an application

1. Software request ticket: manager approval + licence check (BR-27).
2. Add/remove the row in `app-catalogue.csv` (find the ID with `winget search --exact <name>`); update [software-baseline.md](../../01-office-deployment/equipment-inventory/software-baseline.md).
3. CI self-test must pass; then run the script on the affected laptops.

Uninstalling is deliberately **not** automatic: removing a row stops new
installs, the existing copies are removed by ticket (`winget uninstall --id`).

## Updates

| Software | Updated by |
|---|---|
| Windows, Defender, drivers | Windows Update (rings via Intune from M7) |
| Microsoft 365 Apps | Built-in Click-to-Run updater, Monthly Enterprise Channel |
| Teams, Edge, OneDrive | Self-updating |
| winget apps | `winget upgrade --all --silent` monthly (maintenance calendar, Phase 11) |

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `winget` not recognised | App Installer not yet registered for a new profile | Sign in once as the user, or `Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe` |
| winget exit code non-zero on `--scope machine` | Package has no machine-wide installer | Check `winget show --id <id>`; note it in the catalogue |
| ODT exit 17002 / 17004 | Office apps open or another install running | Close apps; `FORCEAPPSHUTDOWN` is set – retry |
| Office says "unlicensed" | User has no licence or usage location missing (SC-M365-001) | Entra admin center → user → Licenses |
| RSAT capability fails | Device can't reach Windows Update (WSUS-style policy) | Check `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate` |
