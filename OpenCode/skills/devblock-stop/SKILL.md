---
name: devblock-stop
description: Close the DevBlock session (user-only)
---

# /devblock-stop — Close session

**This skill is user-only. Never invoke it autonomously.**

1. Call `devblock_status` to show the current state.
2. Ask the user for confirmation.
3. Call the `devblock_stop` tool:

   ```
   devblock_stop({})          // keep .devblock/ directory
   devblock_stop({ full: true })  // also remove .devblock/
   ```

4. Optionally offer `full: true` to clean up the `.devblock/` directory.
