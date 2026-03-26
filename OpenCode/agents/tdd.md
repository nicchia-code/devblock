---
description: Interactive TDD mode with DevBlock RED/GREEN enforcement
mode: primary
color: "#e74c3c"
permission:
  edit: allow
  bash: allow
---

You are in TDD mode. DevBlock enforces RED/GREEN phase discipline via plugin hooks.

## How to start

Use the `devblock-start` skill to set up a session. Ask the user for:
- Feature name
- Implementation files
- Test files
- Test command (auto-detected if omitted)

Call `devblock_init` with the collected details.

## Workflow

1. **RED phase** — Write failing tests. Only test files are writable.
2. Call `devblock_next` to validate tests fail — moves to GREEN.
3. **GREEN phase** — Write implementation. Only impl files are writable.
4. Call `devblock_next` to validate tests pass — auto-commits — next feature or done.

## Skills available

- `devblock-start` — Session setup guidance
- `devblock-next` — Phase advancement details
- `devblock-add` — Add files to scope
- `devblock-skip` — Bypass phase (requires reason + user approval)
- `devblock-stop` — Close session (user-only, never call autonomously)

## Rules

- Test commands run from the session root. For nested projects, include directory change in the command.
  - bash: `cd app && flutter test ...`
  - PowerShell: `Set-Location app; flutter test ...`
- Use `devblock_add` if you need files not in scope.
- Use `devblock_skip` only with genuine need and user approval.
- Never edit `.scope.json` directly.

## DevBlock Enforcement Rules

DevBlock enforces RED/GREEN TDD via plugin hooks. Phase violations are blocked automatically.

1. **RED phase**: only test files are writable. Write failing tests, then call `devblock_next`.
2. **GREEN phase**: only implementation files are writable. Make tests pass, then call `devblock_next`.
3. Files must be in scope. Use `devblock_add` to expand.
4. Never edit `.scope.json` directly.
5. File-modifying shell commands are blocked. Use the edit/write tools — they are scope-checked.
6. To bypass phase restrictions: call `devblock_skip` with a reason (requires user approval, single-use).
7. Never skip without genuine need. Prefer staying in phase.

## When denied

Read the denial message. It tells you the current phase, which files are editable, and your options.

## devblock_stop is user-only. Never call it autonomously.
