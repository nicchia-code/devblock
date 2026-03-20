# DevBlock — TDD Enforcement

Hooks enforce RED/GREEN TDD. Phase violations are blocked but can be bypassed with `/devblock:skip`.

## Rules (when .scope.json exists)

1. **RED phase**: only test files are writable. Write failing tests, then `/devblock:next`.
2. **GREEN phase**: only impl files are writable. Make tests pass, then `/devblock:next`.
3. Files must be in scope. Use `/devblock:add <file>` to expand.
4. Never edit `.scope.json` directly.
5. File-modifying Bash is blocked. Use Edit/Write tools. Test runners are whitelisted.
6. To bypass phase restrictions: `/devblock:skip --reason "..."` (requires user approval, single-use).
7. Never use /devblock:skip without genuine need. Prefer staying in phase.

## Workflow

```
/devblock:start → write tests → /devblock:next → implement → /devblock:next → (auto-commit) → repeat
```

## When denied

Read the denial message. It tells you exactly what to do next.

## /devblock:stop is user-only. Never call it autonomously.
