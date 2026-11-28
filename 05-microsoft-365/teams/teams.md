# Microsoft Teams: Teams, Channels, Policies and Meeting Rooms

| Field | Value |
|---|---|
| Document ID | M365-PRC-005 |
| Owner | IT Specialist |
| Status | Draft – becomes Approved after the lab tenant is built |
| Last reviewed | 2026-11-27 |
| Related requirements | BR-03, BR-07, BR-09, BR-26 |
| Source data | [teams.csv](teams.csv) |

## 1. Teams

| Team | Group (`grp-`) | Members (dynamic rule) | Owners | Channels | Guests |
|---|---|---|---|---|---|
| TechCorp | grp-all | every synced, enabled user | hange.zoe, erwin.smith | Announcements, Social, IT Help | No |
| Management | grp-management | `department = Management` | erwin.smith, hange.zoe | Board, Planning | No |
| Finance | grp-finance | `department = Finance` | dot.pixis, nile.dok | Month-End, Audit | No |
| HR | grp-hr | `department = Human Resources` | historia.reiss, sasha.blouse | Recruitment, Policies | No |
| Sales & Marketing | grp-sales | `department = Sales & Marketing` | jean.kirstein, connie.springer | Proposals, Marketing, Client Demos | **Yes** |
| Development | grp-development | `department = Software Development` | levi.ackerman, armin.arlert | Releases, Code Review, Client Projects | No |
| Customer Support | grp-support | `department = Customer Support` | petra.ral, oluo.bozado | Escalations, Knowledge Base | No |

Example rule: `(user.department -eq "Finance") and (user.accountEnabled -eq true)`.

### Why dynamic groups

The `department` attribute is set in AD from `employees.csv`
(`Deploy-TechCorpAd.ps1`) and synced. A Microsoft 365 group with a dynamic
rule on it (Entra ID P1 – included in Business Premium) means **nobody
maintains team membership**: joiners appear, movers move, leavers
(`accountEnabled = false`) drop out. The cost: membership is only as good as
the department attribute (SC-M365-004), and owners are still set by hand
(two per team, CI-checked).

IT has no department team (one person); IT requests use the *IT Help* channel
in the company-wide team and the ticket process (Phase 8).

## 2. Creating them

```powershell
Connect-MgGraph -Scopes 'Group.ReadWrite.All', 'Directory.ReadWrite.All', 'User.ReadWrite.All'
Connect-MicrosoftTeams
.\07-powershell\microsoft-365\Deploy-TechCorpM365.ps1 -Skip Users,Licensing,Mail,SharePoint -WhatIf
.\07-powershell\microsoft-365\Deploy-TechCorpM365.ps1 -Skip Users,Licensing,Mail,SharePoint
```

Per team: dynamic M365 group → owners → guest setting (`AllowToAddGuests = false`
unless the team allows guests) → team → channels. A new group can take a few
minutes before `New-Team` accepts it – re-running the script continues where it stopped.

## 3. Tenant policies (Teams admin center)

| Area | Setting | Value |
|---|---|---|
| Teams creation | Who can create teams | Nobody but admins (M365 group creation restricted in [tenant-setup.md](../tenant/tenant-setup.md) step 6) |
| Guest access | Teams guest access | On (only teams whose group allows guests can add them – Sales) |
| External access | Federation with other Microsoft 365 orgs | **Allow only specific domains** – client domains added by ticket; Teams consumer accounts blocked |
| Meetings | Anonymous users can join | Yes (clients without accounts), **lobby** for everyone outside the org; only organisers can present by default |
| Meetings | Recording | Allowed; recordings saved to OneDrive/SharePoint, expire after 120 days |
| Messaging | Chat with external users | Federated domains only |
| Apps | Third-party apps | Blocked by default; allowed per request |
| Calling | Teams Phone | Not in scope (Support uses their existing phone service) |

## 4. Meeting rooms

See [desks-and-meeting-rooms.md §3](../../04-endpoint-management/peripherals/desks-and-meeting-rooms.md#3-meeting-rooms-teams-rooms):
room mailboxes `room-mr1@` / `room-mr2@`, Teams Rooms Basic licence, sign-in on the device.

## Verification

| Test | Expected |
|---|---|
| `Test-TechCorpM365.ps1` Teams rows | PASS (rule, team, visibility, owners, channels) |
| Entra admin center → grp-finance → Members | dot.pixis, nile.dok, hitch.dreyse |
| Change a lab user's department in AD, delta sync | Moves to the new team within the dynamic-group processing time |
| A Sales owner adds a guest | Allowed; HR owner trying the same is blocked |
| External user joins a meeting link | Waits in the lobby |

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| User not in their department team | Department attribute differs from the rule | SC-M365-004 |
| "Group not found" from `New-Team` | Group provisioning still replicating | Wait and re-run |
| Owner can't add members | Dynamic groups don't accept manual members | Change the AD attribute, or use a guest/assigned team |
| Guests can't be added to a team that allows them | Tenant guest settings / group setting | Teams admin center guest access; `Get-MgGroupSetting` |
