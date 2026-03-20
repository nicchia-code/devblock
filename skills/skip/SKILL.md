---
name: skip
description: Bypass TDD phase restriction with justification and user approval
user_invocable: true
---

# /devblock:skip

1. The agent MUST have a clear reason for bypassing the current TDD phase.

2. Extract the reason from context (why is this edit needed outside phase?).

3. **Ask the user for confirmation** using AskUserQuestion:
   - Question: "I need to edit outside the current TDD phase. Reason: {reason}. Allow this bypass?"
   - Options: "Yes, allow this skip" / "No, stay in phase"

4. If user approves:
   ```bash
   bash .devblock/devblock-ctl.sh skip --reason "<reason>"
   ```

5. If user denies: acknowledge and continue working within the current phase.

6. After skip is approved, make the ONE edit that required the bypass. The token is single-use.
