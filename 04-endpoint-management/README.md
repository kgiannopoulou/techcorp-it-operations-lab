# 04 – Endpoint Management

**Status:** ✅ Milestone 6 – designed, scripted and documented · 🧪 lab execution and evidence pending

Building and supporting Windows 11 laptops to the
[workstation standard](../01-office-deployment/workstation-deployment/workstation-standard.md):
clean install, domain join, hybrid Entra join, GPO baseline, BitLocker,
software from a CI-validated catalogue, printers, desks and meeting rooms.

| Document | ID | Contents |
|---|---|---|
| [windows-11/deployment-strategy.md](windows-11/deployment-strategy.md) | END-REF-001 | Why clean install + domain join + script (and Autopilot later), lifecycle, who configures what |
| [windows-11/laptop-build.md](windows-11/laptop-build.md) | END-PRC-001 | Step-by-step build incl. the VirtualBox lab VM (vTPM, Secure Boot), BitLocker escrow, handover |
| [software-installation/software-deployment.md](software-installation/software-deployment.md) | END-PRC-002 | App catalogue, winget, Office Deployment Tool, RSAT, adding apps, updates |
| [drivers/drivers-and-firmware.md](drivers/drivers-and-firmware.md) | END-PRC-003 | Driver sources per tier, BIOS updates with BitLocker suspended |
| [printers/printing.md](printers/printing.md) | END-PRC-004 | Print server on TC-FS01 (END-CHG-001), GPP printers, Point-and-Print, scan-to-e-mail |
| [peripherals/desks-and-meeting-rooms.md](peripherals/desks-and-meeting-rooms.md) | END-PRC-005 | Desk checks, headsets, Teams Rooms resource accounts |
| [troubleshooting/endpoint-troubleshooting.md](troubleshooting/endpoint-troubleshooting.md) | END-REF-002 | Commands and symptom table for laptops and M365 clients |

## Source data (CI-validated)

| File | Contents |
|---|---|
| [software-installation/app-catalogue.csv](software-installation/app-catalogue.csv) | 22 apps: method, ID, target (All / department / tier), licence |
| [software-installation/m365-apps-configuration.xml](software-installation/m365-apps-configuration.xml) | Office Deployment Tool configuration |

Scripts: [07-powershell/endpoint](../07-powershell/endpoint/) –
`Install-TechCorpBaseline.ps1` (installs, `-SelfTest` in CI) and
`Test-TechCorpEndpoint.ps1` (read-only build check).

## Design changes in Milestone 6

| ID | Change | Why |
|---|---|---|
| [END-CHG-001](printers/printing.md#design-change-end-chg-001--print-server-on-tc-fs01) | Print server on TC-FS01 instead of direct IP printing | Driver installs need admin rights since PrintNightmare; TC-PRN02 must be Finance-only |

Microsoft 365 side: [05-microsoft-365](../05-microsoft-365/). Intune,
compliance, update rings and Autopilot follow in M7.
