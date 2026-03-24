#!/usr/bin/env bash
# install.sh — Install DevBlock for Cursor (Linux/Mac/WSL)
# Installs skills + hooks globally to ~/.cursor/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST="$HOME/.cursor"
SKILLS_DIR="$DEST/skills"
HOOKS_SCRIPTS="$DEST/hooks/devblock"

die() { echo "ERROR: $*" >&2; exit 1; }
ok() { echo "  OK: $*"; }

# Check prerequisites
command -v jq &>/dev/null || die "jq is required. Install it with: sudo apt install jq (or brew install jq)."

# Validate source — we read from the repo root (Claude Code plugin format)
[[ -f "$REPO_ROOT/CLAUDE.md" ]] || die "Cannot find CLAUDE.md in $REPO_ROOT. Run from Cursor/ directory."
[[ -d "$REPO_ROOT/skills" ]] || die "Cannot find skills/ in $REPO_ROOT."
[[ -d "$REPO_ROOT/hooks" ]] || die "Cannot find hooks/ in $REPO_ROOT."
[[ -f "$REPO_ROOT/scripts/devblock-ctl.sh" ]] || die "Cannot find scripts/devblock-ctl.sh in $REPO_ROOT."

echo "Installing DevBlock to: $DEST"
echo ""

# ─── 1. Skills ───────────────────────────────────────────────────────────────

echo "Installing skills..."
for skill_dir in "$REPO_ROOT"/skills/*/; do
  skill_name="$(basename "$skill_dir")"
  dest_skill="$SKILLS_DIR/devblock-$skill_name"
  mkdir -p "$dest_skill"
  cp "$skill_dir/SKILL.md" "$dest_skill/SKILL.md"
  ok "devblock-$skill_name"
done

# ─── 2. Hook scripts (Cursor-adapted versions) ──────────────────────────────

echo ""
echo "Installing hook scripts..."
mkdir -p "$HOOKS_SCRIPTS"
cp "$SCRIPT_DIR/hooks/devblock/scope-guard.sh" "$HOOKS_SCRIPTS/scope-guard.sh"
cp "$SCRIPT_DIR/hooks/devblock/devblock-ctl.sh" "$HOOKS_SCRIPTS/devblock-ctl.sh"
chmod +x "$HOOKS_SCRIPTS/"*.sh
ok "scope-guard.sh (Cursor format)"
ok "devblock-ctl.sh (Cursor paths)"

# ─── 3. Register hooks in hooks.json (Cursor format) ────────────────────────

echo ""
echo "Registering hooks..."

HOOKS_JSON="$DEST/hooks.json"

HOOKS_CONFIG='{
  "version": 1,
  "hooks": {
    "preToolUse": [
      {
        "command": "bash '"$HOOKS_SCRIPTS"'/scope-guard.sh",
        "type": "command",
        "matcher": "Write",
        "timeout": 10,
        "failClosed": false
      }
    ],
    "beforeShellExecution": [
      {
        "command": "bash '"$HOOKS_SCRIPTS"'/scope-guard.sh --shell",
        "type": "command",
        "timeout": 10,
        "failClosed": false
      }
    ]
  }
}'

if [[ -f "$HOOKS_JSON" ]]; then
  # Merge: remove old devblock hooks, add new ones
  MERGED=$(echo "$HOOKS_CONFIG" | jq --slurpfile existing "$HOOKS_JSON" '
    ($existing[0].hooks // {}) as $eh |
    .hooks.preToolUse = [($eh.preToolUse // [])[] | select(.command | test("devblock") | not)] + .hooks.preToolUse |
    .hooks.beforeShellExecution = [($eh.beforeShellExecution // [])[] | select(.command | test("devblock") | not)] + .hooks.beforeShellExecution |
    . + {version: ($existing[0].version // 1)}
  ')
  echo "$MERGED" > "$HOOKS_JSON"
  ok "Merged hooks into existing $HOOKS_JSON"
else
  echo "$HOOKS_CONFIG" > "$HOOKS_JSON"
  ok "Created $HOOKS_JSON"
fi

# ─── 4. Write Cursor-adapted start skill (replaces Claude Code version) ──────

echo ""
echo "Writing Cursor-adapted skills..."

CTL="$HOOKS_SCRIPTS/devblock-ctl.sh"

cat > "$SKILLS_DIR/devblock-start/SKILL.md" << SKILL_EOF
---
name: start
description: Start a DevBlock TDD session
user_invocable: true
---

# /devblock:start — Start TDD session

## Steps

1. DevBlock is installed globally. The controller is at \`$CTL\`.

2. **Check for an existing plan first.** Look in \`.cursor/plans/\` and \`~/.cursor/plans/\` for recent \`.plan.md\` files related to the current project. If a plan exists, extract feature name, files, tests, and queue from it — propose these to the user for confirmation instead of asking from scratch.

3. If no plan exists (or the plan doesn't cover TDD details), ask the user for:
   - **Feature name** (short description)
   - **Implementation files** (paths or globs — resolve with Glob)
   - **Test files** (propose based on project conventions)
   - **Test command** (detect from package.json, Makefile, etc.)
   - **Queue** (optional: additional features as \`name | files | tests\`)

4. Build JSON and call:
   \`\`\`bash
   bash $CTL init '<JSON>'
   \`\`\`

   JSON format:
   \`\`\`json
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
   \`\`\`

5. Confirm session started. Begin writing failing tests immediately.

> **Note:** If you need to edit outside the current phase, use \`/devblock-skip\` — it requires a reason and user approval.
SKILL_EOF
ok "devblock-start (Cursor-adapted with plan detection)"

# Patch remaining skills: replace .devblock/ paths with global paths
for skill_md in "$SKILLS_DIR"/devblock-*/SKILL.md; do
  sed -i "s|bash .devblock/devblock-ctl.sh|bash $CTL|g" "$skill_md"
  sed -i "s|/devblock:skip|/devblock-skip|g" "$skill_md"
  sed -i "s|/devblock:next|/devblock-next|g" "$skill_md"
  sed -i "s|/devblock:start|/devblock-start|g" "$skill_md"
  sed -i "s|/devblock:stop|/devblock-stop|g" "$skill_md"
  sed -i "s|/devblock:add|/devblock-add|g" "$skill_md"
done
ok "All skills patched with global paths and Cursor skill names"

# ─── Done ────────────────────────────────────────────────────────────────────

echo ""
echo "DevBlock installed successfully!"
echo ""
echo "Skills installed:"
ls -1 "$SKILLS_DIR" | grep devblock | sed 's/^/  /'
echo ""
echo "How to use:"
echo "  1. Open any project in Cursor"
echo "  2. Type /devblock-start to begin a TDD session"
echo "  3. Hooks enforce RED/GREEN phase automatically"
echo ""
echo "To uninstall:"
echo "  rm -rf $HOOKS_SCRIPTS"
echo "  rm -rf $SKILLS_DIR/devblock-*"
echo "  Edit $HOOKS_JSON to remove devblock entries"
