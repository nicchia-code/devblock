---
name: start
description: Start a DevBlock TDD session
user_invocable: true
---

# /devblock:start — Start TDD session

## Steps

1. Check `.devblock/devblock-ctl.sh` exists. If not, run install:
   ```bash
   bash <plugin-scripts-path>/devblock-ctl.sh install
   ```
   Find the plugin scripts path by searching `~/.claude/plugins/cache/` for `devblock*/scripts/devblock-ctl.sh`.

2. Ask the user (via AskUserQuestion) for:
   - **Feature name** (short description)
   - **Implementation files** (paths or globs — resolve with Glob)
   - **Test files** (propose based on project conventions)
   - **Test command** (detect from package.json, Makefile, etc.)
   - **Queue** (optional: additional features as `name | files | tests`)

3. Build JSON and call:
   ```bash
   bash .devblock/devblock-ctl.sh init '<JSON>'
   ```

   JSON format:
   ```json
   {
     "current": {
       "name": "Feature name",
       "phase": "red",
       "files": ["src/module.ts"],
       "tests": ["tests/module.test.ts"],
       "test_command": "npm test -- tests/module.test.ts"
     },
     "queue": []
   }
   ```

4. Confirm session started. Begin writing failing tests immediately.
