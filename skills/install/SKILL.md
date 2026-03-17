---
name: install
description: "Initialize DevBlock in the current project: copies scope-guard, plan-trigger and devblock-ctl to .devblock/"
user_invocable: true
---

# /devblock:install — Initialize DevBlock in a Project

## What this does

Copies the DevBlock scripts (`scope-guard.sh`, `plan-trigger.sh` and `devblock-ctl.sh`) into a local `.devblock/` folder in the current project. This is required before using any other DevBlock features.

## Steps

1. Check if `.devblock/devblock-ctl.sh` already exists. If yes, ask the user if they want to reinstall (update).

2. Find `devblock-ctl.sh` in the Claude plugin cache:
   ```
   ~/.claude/plugins/cache/devblock*/devblock/*/scripts/devblock-ctl.sh
   ```
   Use Glob to find it. If multiple versions exist, use the one with the highest version number.

3. Run via Bash:
   ```
   bash <path-to-devblock-ctl.sh> install
   ```

4. Verify `.devblock/scope-guard.sh`, `.devblock/plan-trigger.sh` and `.devblock/devblock-ctl.sh` exist.

5. Inform the user that DevBlock is ready. Suggest creating a plan with `/plan` — when the plan is approved, DevBlock will automatically offer to start a TDD session.
