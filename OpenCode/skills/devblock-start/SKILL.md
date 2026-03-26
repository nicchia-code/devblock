---
name: devblock-start
description: Start a DevBlock TDD session
---

# /devblock-start — Start TDD session

## Steps

1. Ask the user for:
   - **Feature name** (short description)
   - **Implementation files** (paths — resolve with glob if needed)
   - **Test files** (propose based on project conventions)
   - **Test command** (if omitted, `devblock_init` auto-detects it)
   - **Queue** (optional: additional features to implement after this one)

    Be careful with the test execution path: `devblock_next` runs the stored test command from the session root (the directory where DevBlock was started).

    For nested apps or packages:
    - start DevBlock inside the nested project directory, or
    - provide a command that changes directory explicitly, such as:
      - bash: `cd app && flutter test test/foo_test.dart`
      - PowerShell: `Set-Location app; flutter test test/foo_test.dart`

2. Call the `devblock_init` tool:

   ```
   devblock_init({
     name: "feature name",
     files: ["src/module.ts"],
     tests: ["tests/module.test.ts"],
     test_command: "npm test"  // optional — auto-detected if omitted
   })
   ```

3. Read the output — it confirms the session and tells you what to do next.

4. Begin writing failing tests immediately (RED phase).

> If you need to edit outside the current phase, use `/devblock-skip` — it requires a reason and user approval.
