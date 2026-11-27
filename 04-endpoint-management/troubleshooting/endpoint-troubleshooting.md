# Endpoint and Microsoft 365 Client Troubleshooting

| Field | Value |
|---|---|
| Document ID | END-REF-002 |
| Owner | IT Specialist |
| Status | Draft – extended after every lab session |
| Last reviewed | 2026-11-27 |

First step for any "my laptop is weird" ticket: run
[Test-TechCorpEndpoint.ps1](../../07-powershell/endpoint/Test-TechCorpEndpoint.ps1) –
it checks identity, security, policy, time and software in one go.

## 1. Command cheat sheet

| Question | Command |
|---|---|
| Domain / Entra join state, PRT | `dsregcmd /status` (look at *AzureAdJoined*, *DomainJoined*, *AzureAdPrt*) |
| Which DC / site am I using? | `nltest /dsgetdc:corp.techcorp.example` |
| Which GPOs applied? | `gpresult /r` · `gpresult /h gp.html` |
| BitLocker | `manage-bde -status` · `Get-BitLockerVolume` |
| Recovery key (IT laptop, `wadm-`) | ADUC → computer → *BitLocker Recovery*, or Entra admin center → Devices → *Recovery keys* |
| LAPS password (`wadm-`) | `Get-LapsADPassword -Identity TC-LT-014 -AsPlainText` |
| Defender | `Get-MpComputerStatus` |
| Installed apps | `winget list` |
| Office version / channel | *File → Account* · `HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration` |
| Recent errors | `Get-WinEvent -LogName System -MaxEvents 50 \| Where-Object Level -le 2` |
| Reliability history | `perfmon /rel` |

## 2. Symptom → cause table

| Symptom | Most likely cause | Check / fix |
|---|---|---|
| Asks for the BitLocker recovery key at boot | Firmware/BIOS update or TPM change without suspending BitLocker | SC-HW-001 – key from AD/Entra, then `Suspend-BitLocker` next time |
| Only one monitor on the dock | Dock firmware / MST, or a USB-C port without DisplayPort Alt-Mode | SC-HW-002 |
| Outlook/Teams keep asking to sign in | No PRT – device not hybrid joined | `dsregcmd /status` (SC-WIN-004) |
| "Your account doesn't have a licence" in Office | Licence not assigned (usage location, group) | SC-M365-001 |
| Shared mailbox missing in Outlook | Auto-mapping takes up to an hour / permission via group | SC-M365-005 |
| New colleague not in their department team | Department attribute wrong in AD → dynamic rule doesn't match | SC-M365-004 |
| OneDrive won't sync on a home PC | Sync restricted to domain-joined PCs (by design) | Use the web or the company laptop |
| Known folders not moved | `C-Workstations-OneDrive` not applied / tenant ID missing | `gpresult`; `HKLM\Software\Policies\Microsoft\OneDrive` |
| Teams slow / stale after an update | Corrupt client cache | Quit Teams → *Settings → Apps → Microsoft Teams → Advanced options → Reset* |
| Outlook profile corrupted | – | New profile via *Control Panel → Mail*; autodiscover recreates it |
| Slow first logon on a new laptop | Policy + OneDrive KFM + Office first run | Normal once; check `gpresult` timing if repeated |
| Can't install software | Standard user by design | Software request ticket (BR-14) |

## 3. Profile and data

Because Known Folder Move puts Desktop/Documents/Pictures in OneDrive,
"rebuilding a profile" or "swapping a laptop" loses nothing that the user saw
in those folders. Check before any rebuild: OneDrive icon → *Settings →
Account* shows the folders as *backed up*.
