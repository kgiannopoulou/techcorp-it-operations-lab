# Lessons Learned: Milestone 5 – Windows Server and Active Directory

| Field | Value |
|---|---|
| Document ID | DOC-LL-002 |
| Related phase / scenario | Phases 2–3 (M5), SC-WIN-002, SC-ACC-003 |
| Date | 2026-11-27 |

## What happened

Designed and scripted the domain, OUs, users, groups, Group Policy and file
permissions. As in Milestone 4, the identity design was turned into data
(CSV) plus scripts, and an offline model of effective access was built so the
permission design could be **tested in CI before any server exists**.

## What went well

- `employees.csv` from Milestone 2 drove everything: accounts, OU placement,
  managers, the managers group (CI checks it equals "people with direct reports").
- Writing `access-tests.csv` first ("Nile must **not** see Payroll") and
  letting the model compute the answer turned vague intentions into checks.
- One plan script used by deploy *and* verify scripts – no second copy of
  the design that can drift.

## What went wrong / was harder than expected

| Problem | Found when | Change |
|---|---|---|
| One `adm-` account would be Domain Admin *and* used on laptops for support | Writing the user-rights GPO | **WIN-CHG-001** – `wadm-` account, DA denied on workstations |
| `dfs\IT$` – a `$` hides SMB shares, not DFS namespace folders | Writing the namespace procedure | **WIN-CHG-002** – namespace folder `IT` |
| `Sales & Marketing` as an OU/group name needs escaping everywhere | First run of the plan script | **WIN-CHG-003** – department codes |
| My first naming regex rejected `DL_FS_Finance_RW` (two underscores before the access suffix) | Self-test | Pattern now models `DL_<Type>_<Resource>[-<Sub>]_<Access>` |
| `Set-ADDefaultDomainPasswordPolicy` looks like the obvious tool but is overwritten by the Default Domain Policy GPO | Researching the password policy | Policy set in the GPO, script only verifies |
| Prestaging computer objects as a Domain Admin conflicts with joining them as `wadm-` (account re-use hardening) | Designing the join procedure | No prestaging: `wadm-` is delegated *create computer objects* and joins with `-OUPath` |
| Restoring DC snapshots causes USN rollback | Planning the VirtualBox lab | Snapshot rules in ad-ds-deployment.md |

## What I learned (technical)

- GPO **user** settings follow the user object's OU, not the computer's (SC-WIN-003).
- Since MS16-072 a security-filtered GPO needs *Authenticated Users: Read* (SC-WIN-002).
- "Modify" on a department root lets users delete the root itself – split into an inherit-only Modify + a this-folder-only create/read entry.
- *Bypass traverse checking* means "no access to the parent" ≠ "no access to the child" (SC-ACC-003).
- Group membership changes reach a user only with a new Kerberos ticket (SC-ACC-002).

## What I will do differently

| Action | Where it is documented | Done |
|---|---|---|
| Write expected-access tests before ACLs | access-tests.csv | ☑ |
| Keep GPO settings as data where the module allows, document the rest click-by-click | gpo-registry-settings.csv, gpo-procedures.md | ☑ |
| Run the M4 + M5 lab end-to-end and replace "Designed" with "Solved" + evidence | 14-scenarios/scenario-index.md | ☐ |
| Run PSScriptAnalyzer locally before pushing (currently only in CI) | 07-powershell/README.md | ☐ |
