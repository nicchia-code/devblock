---
name: devblock-skip
description: Bypass TDD phase restriction with justification and user approval
---

# /devblock-skip

1. You MUST have a clear reason for bypassing the current TDD phase.

2. **Ask the user for confirmation** before proceeding:
   - Explain why the edit is needed outside the current phase.
   - Options: "Yes, allow this skip" / "No, stay in phase"

3. If user approves, call the `devblock_skip` tool:

   ```
   devblock_skip({ reason: "Need to fix import path in impl file before tests can compile" })
   ```

4. If user denies: acknowledge and continue working within the current phase.

5. After skip is approved, make the ONE edit that required the bypass. The token is single-use.
