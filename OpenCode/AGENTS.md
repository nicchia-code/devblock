<!-- BEGIN DEVBLOCK -->
# DevBlock — TDD Enforcement

DevBlock enforces RED/GREEN TDD via plugin hooks. Phase violations are blocked automatically.

## Rules (when .scope.json exists)

1. **RED phase**: only test files are writable. Write failing tests, then call `devblock_next`.
2. **GREEN phase**: only implementation files are writable. Make tests pass, then call `devblock_next`.
3. Files must be in scope. Use `devblock_add` to expand.
4. Never edit `.scope.json` directly.
5. File-modifying shell commands are blocked. Use the edit/write tools — they are scope-checked.
6. To bypass phase restrictions: call `devblock_skip` with a reason (requires user approval, single-use).
7. Never skip without genuine need. Prefer staying in phase.

## Workflow

```
devblock_init → write tests → devblock_next → implement → devblock_next → (auto-commit) → repeat
```

## When denied

Read the denial message. It tells you the current phase, which files are editable, and your options.

## devblock_stop is user-only. Never call it autonomously.
<!-- END DEVBLOCK -->
