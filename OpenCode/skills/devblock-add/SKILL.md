---
name: devblock-add
description: Add a file to the current TDD scope
---

# /devblock-add — Add file to scope

Usage: `/devblock-add <file>`

1. Resolve the file path.
2. Call the `devblock_add` tool:

   ```
   devblock_add({ file: "src/new-module.ts" })
   ```

   The file type (impl/test) is **auto-detected** from naming conventions.
   Override with `type: "test"` or `type: "impl"` if needed.

3. The tool confirms what was added and the detected type.
