# Documentation Standards

| Field | Value |
|---|---|
| Document ID | DOC-STD-001 |
| Owner | IT Specialist |
| Status | Approved |
| Last reviewed | 2026-11-26 |

These rules apply to every file in the repository. They exist so that a
document written today is still usable in two years – by me or by whoever
replaces me.

## 1. Document types

| Type | Purpose | Template | Lives in |
|---|---|---|---|
| Procedure | Step-by-step "how to configure / do X" | [procedure-template.md](../templates/procedure-template.md) | `02`–`13` |
| Scenario | A problem received, investigated and solved | [scenario-template.md](../templates/scenario-template.md) | `14-scenarios` |
| Ticket | A single user request or incident | [ticket-template.md](../templates/ticket-template.md) | `06-helpdesk` |
| Lessons learned | What went wrong / right and what changes | [lessons-learned-template.md](../templates/lessons-learned-template.md) | `15-documentation/lessons-learned` |
| Report | Deployment, incident or maintenance report | [report-template.md](../templates/report-template.md) | `16-reports` |
| Reference | Profiles, plans, inventories, standards | (free form, metadata table required) | anywhere |

## 2. Every document starts with a metadata table

```markdown
| Field | Value |
|---|---|
| Document ID | NET-PRC-003 |
| Owner | IT Specialist |
| Status | Draft / Approved / Superseded |
| Last reviewed | YYYY-MM-DD |
```

### Document ID prefixes

| Prefix | Area | Prefix | Area |
|---|---|---|---|
| `CO` | Company overview | `SEC` | Cybersecurity |
| `DEP` | Office deployment | `BKP` | Backup & DR |
| `NET` | Network infrastructure | `MON` | Monitoring & maintenance |
| `WIN` | Windows Server / AD | `ASM` | Asset management |
| `END` | Endpoint management | `POL` | Policies & procedures |
| `M365` | Microsoft 365 | `CAL` | Maintenance calendar |
| `HD` | Helpdesk | `SC` | Scenarios |
| `PS` | PowerShell | `DOC` | Documentation / standards |

Suffix: `-PRC` procedure, `-REF` reference, `-STD` standard, `-RPT` report,
followed by a three-digit number. Scenarios use `SC-<AREA>-<NNN>`
(e.g. `SC-NET-004`).

## 3. Writing style

- Write for a competent colleague who has **never seen this environment**.
- Imperative mood for steps: "Open DHCP Manager", not "You should open…".
- One action per numbered step. Put the expected result directly under it.
- Commands go in fenced code blocks with a language tag (`powershell`, `text`, `bash`).
- State **why**, not only what – one sentence of reasoning per design decision.
- Use tables for anything with more than three comparable items.
- Prefer British/International English spelling consistently.

## 4. Files and folders

- File names: `lowercase-kebab-case.md`. No spaces, no capitals, no dates in names
  (dates go in the metadata table). Exception: data files (`*.csv`) and scripts
  (`Verb-Noun.ps1`).
- Each top-level folder has a `README.md` that says what belongs there and links to its contents.
- Do not create empty placeholder documents – a file is added when it has real content.
- Structured data (employees, inventory, IP plan) lives in **CSV** and is the
  single source of truth; Markdown tables summarise it.

## 5. Diagrams

- Prefer **Mermaid** inside Markdown (renders on GitHub, diff-able, no binary files).
- Use draw.io (`.drawio` + exported `.png`) only when Mermaid cannot express it;
  store both in `15-documentation/diagrams/`.

## 6. Evidence and screenshots

- Screenshots go in `15-documentation/screenshots/<phase>/` named
  `<doc-id>-<step>-<short-desc>.png` (e.g. `win-prc-002-05-dhcp-scope.png`).
- Only real lab output is committed. No mock-ups.
- **Sanitise before committing:** no real public IPs, tenant IDs, e-mail
  addresses, licence keys, passwords or QR codes for MFA.

## 7. Security rules for this repository

- Never commit passwords, keys, `.pfx`, `.rdp`, `.kdbx` or tenant secrets
  (see [.gitignore](../../.gitignore)).
- Example passwords are written as `<REDACTED>` or `P@ssw0rd-EXAMPLE-ONLY`.
- All names and domains are fictional; the domain is `techcorp.example`.

## 8. Review and change

- Status `Draft` until the procedure has been executed successfully in the lab at least once.
- Update `Last reviewed` whenever content is verified, even if nothing changes.
- Commit messages follow `<area>: <what changed>`, e.g. `net: add VLAN 40 printer subnet`.
