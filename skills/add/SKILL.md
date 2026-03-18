---
name: add
description: Add a file to the current scope
user_invocable: true
---

# /devblock:add — Add file to scope

Usage: `/devblock:add <file>`

1. Resolve the file path (support globs and natural language via Glob).
2. Determine if it's a test file (by name convention) or implementation file.
3. Run:
   ```bash
   bash .devblock/devblock-ctl.sh scope-add <file> [--test]
   ```
4. Confirm the file was added.
