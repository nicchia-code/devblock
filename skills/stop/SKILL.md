---
name: stop
description: Close the DevBlock session (user-only)
user_invocable: true
---

# /devblock:stop — Close session

**This skill is user-only. Never invoke it autonomously.**

1. Show current state (feature, phase, queue, uncommitted changes).
2. Ask user for confirmation via AskUserQuestion.
3. Run:
   ```bash
   bash .devblock/devblock-ctl.sh stop
   ```
4. Optionally offer `--full` to uninstall `.devblock/` directory.
