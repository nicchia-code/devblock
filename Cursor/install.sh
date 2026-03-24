#!/usr/bin/env bash
# install.sh — Install DevBlock for Cursor (Linux/Mac/WSL)
# Installs hooks to ~/.cursor/ (user-level, applies to all projects)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.cursor"
HOOKS_DIR="$DEST/hooks/devblock"

die() { echo "ERROR: $*" >&2; exit 1; }
ok() { echo "$*"; }

# Check prerequisites
command -v jq &>/dev/null || die "jq is required. Install it with: sudo apt install jq (or brew install jq)."

# Validate source files
[[ -d "$SCRIPT_DIR/hooks/devblock" ]] || die "Cannot find hooks/devblock/ in $SCRIPT_DIR"

echo "Installing DevBlock to: $DEST"

# Create hooks directory
mkdir -p "$HOOKS_DIR"

# Copy bash scripts
for script in scope-guard.sh devblock-ctl.sh session-start.sh pre-compact.sh session-stop.sh; do
  [[ -f "$SCRIPT_DIR/hooks/devblock/$script" ]] || die "Missing: hooks/devblock/$script"
  cp "$SCRIPT_DIR/hooks/devblock/$script" "$HOOKS_DIR/$script"
done
chmod +x "$HOOKS_DIR/"*.sh

# Generate hooks.json entries for Linux/Mac
DEVBLOCK_HOOKS='{
  "preToolUse": [{
    "command": "bash '"$HOOKS_DIR"'/scope-guard.sh",
    "type": "command",
    "matcher": "Write",
    "timeout": 10,
    "failClosed": false
  }],
  "beforeShellExecution": [{
    "command": "bash '"$HOOKS_DIR"'/scope-guard.sh --shell",
    "type": "command",
    "timeout": 10,
    "failClosed": false
  }],
  "sessionStart": [{
    "command": "bash '"$HOOKS_DIR"'/session-start.sh",
    "type": "command",
    "timeout": 5
  }],
  "preCompact": [{
    "command": "bash '"$HOOKS_DIR"'/pre-compact.sh",
    "type": "command",
    "timeout": 5
  }],
  "stop": [{
    "command": "bash '"$HOOKS_DIR"'/session-stop.sh",
    "type": "command",
    "timeout": 5
  }]
}'

HOOKS_JSON="$DEST/hooks.json"

if [[ -f "$HOOKS_JSON" ]]; then
  # Merge with existing hooks.json
  EXISTING=$(cat "$HOOKS_JSON")

  # Check if devblock hooks already installed (avoid duplicates)
  if echo "$EXISTING" | grep -q "devblock/scope-guard"; then
    ok "DevBlock hooks already present in $HOOKS_JSON — updating..."
    # Remove existing devblock entries and re-add
    # For safety, just overwrite with merged version
  fi

  MERGED=$(echo "$EXISTING" | jq --argjson dh "$DEVBLOCK_HOOKS" '
    .version = (.version // 1) |
    # Remove any existing devblock hooks
    .hooks.preToolUse = [(.hooks.preToolUse // [])[] | select(.command | test("devblock") | not)] |
    .hooks.beforeShellExecution = [(.hooks.beforeShellExecution // [])[] | select(.command | test("devblock") | not)] |
    .hooks.sessionStart = [(.hooks.sessionStart // [])[] | select(.command | test("devblock") | not)] |
    .hooks.preCompact = [(.hooks.preCompact // [])[] | select(.command | test("devblock") | not)] |
    .hooks.stop = [(.hooks.stop // [])[] | select(.command | test("devblock") | not)] |
    # Add devblock hooks
    .hooks.preToolUse += $dh.preToolUse |
    .hooks.beforeShellExecution += $dh.beforeShellExecution |
    .hooks.sessionStart += $dh.sessionStart |
    .hooks.preCompact += $dh.preCompact |
    .hooks.stop += $dh.stop
  ')

  echo "$MERGED" > "$HOOKS_JSON"
  ok "Merged DevBlock hooks into existing $HOOKS_JSON"
else
  # Create new hooks.json
  echo "$DEVBLOCK_HOOKS" | jq '{version: 1, hooks: .}' > "$HOOKS_JSON"
  ok "Created $HOOKS_JSON"
fi

ok ""
ok "DevBlock installed successfully!"
ok ""
ok "How it works:"
ok "  - Hooks are active on ALL projects you open in Cursor"
ok "  - Ask the Cursor agent to start a TDD session"
ok "  - The sessionStart hook injects rules automatically"
ok "  - .scope.json and .devblock/ are created per-project (add to .gitignore)"
ok ""
ok "To uninstall: rm -rf $HOOKS_DIR && edit $HOOKS_JSON to remove devblock entries"
