#!/usr/bin/env bash
# scope-guard.sh — preToolUse / beforeShellExecution hook for DevBlock (Cursor)
# Enforces scope locking and RED/GREEN phase constraints.
# Installed at: ~/.cursor/hooks/devblock/scope-guard.sh
set -o pipefail

PROJECT_DIR="${CURSOR_PROJECT_DIR:-.}"
SCOPE_FILE="$PROJECT_DIR/.scope.json"
DEVBLOCK_DIR="$PROJECT_DIR/.devblock"
CTL="~/.cursor/hooks/devblock/devblock-ctl.sh"

# ─── Helpers ─────────────────────────────────────────────────────────────────

allow() {
  echo '{"permission":"allowed"}'
  exit 0
}

deny() {
  local user_msg="$1"
  local agent_msg="${2:-$user_msg}"
  user_msg=$(printf '%s' "$user_msg" | sed 's/"/\\"/g' | tr '\n' ' ')
  agent_msg=$(printf '%s' "$agent_msg" | sed 's/"/\\"/g' | tr '\n' ' ')
  cat <<EOJSON
{"permission":"denied","user_message":"$user_msg","agent_message":"DEVBLOCK DENIED: $agent_msg"}
EOJSON
  exit 2
}

# ─── Detect hook type ────────────────────────────────────────────────────────

IS_SHELL=false
if [[ "${1:-}" == "--shell" ]]; then
  IS_SHELL=true
fi

# ─── Read hook input ─────────────────────────────────────────────────────────

INPUT=$(cat)

# ─── No session → allow everything ───────────────────────────────────────────

[[ -f "$SCOPE_FILE" ]] || allow
command -v jq &>/dev/null || allow

# ─── Load state ──────────────────────────────────────────────────────────────

CURRENT=$(jq -r '.current // empty' "$SCOPE_FILE" 2>/dev/null || true)
PHASE=$(jq -r '.current.phase // empty' "$SCOPE_FILE" 2>/dev/null || true)

# ─── File Edit Tools (preToolUse) ────────────────────────────────────────────

if [[ "$IS_SHELL" == "false" ]]; then

  TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)

  # Only intercept the Write tool (file editing/creation); allow everything else
  # Cursor tool names: Write, Read, Shell, Delete, Grep, Task
  if [[ "$TOOL_NAME" != "Write" ]]; then
    allow
  fi

  # Extract file path from Write tool input
  FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.target_file // .tool_input.path // empty' 2>/dev/null || true)

  # Normalize path — strip project dir prefix to get relative path
  FILE_PATH="${FILE_PATH#$PROJECT_DIR/}"
  FILE_PATH="${FILE_PATH#./}"

  # Block .scope.json edits
  if [[ "$FILE_PATH" == ".scope.json" || "$FILE_PATH" == *"/.scope.json" ]]; then
    deny "BLOCKED: Do not edit .scope.json directly." \
         "Do not edit .scope.json. To advance phase: bash $CTL next. To add files: bash $CTL scope-add <file>."
  fi

  # Files outside project are not our concern
  [[ "$FILE_PATH" != /* ]] || allow

  # No active feature
  if [[ -z "$CURRENT" || "$CURRENT" == "null" ]]; then
    deny "BLOCKED: No active feature." \
         "No active feature. Start a TDD session first by asking the user for feature details and running: bash $CTL init '<JSON>'"
  fi

  # Check scope membership
  IN_FILES=$(jq --arg f "$FILE_PATH" '.current.files // [] | map(select(. == $f)) | length' "$SCOPE_FILE" 2>/dev/null || echo "0")
  IN_TESTS=$(jq --arg f "$FILE_PATH" '.current.tests // [] | map(select(. == $f)) | length' "$SCOPE_FILE" 2>/dev/null || echo "0")

  # File not in scope
  if [[ "$IN_FILES" -eq 0 && "$IN_TESTS" -eq 0 ]]; then
    SCOPE_LIST=$(jq -r '[(.current.files // [])[], (.current.tests // [])[]] | join(", ")' "$SCOPE_FILE" 2>/dev/null || echo "(unknown)")
    deny "BLOCKED: '$FILE_PATH' not in scope. Scoped files: $SCOPE_LIST" \
         "'$FILE_PATH' not in scope. Add it first: bash $CTL scope-add $FILE_PATH [--test]"
  fi

  # --- Skip token: single-use phase bypass ---
  if [[ -f "$DEVBLOCK_DIR/.skip-token" ]]; then
    rm -f "$DEVBLOCK_DIR/.skip-token"
    allow
  fi

  # RED phase: only test files editable
  if [[ "$IN_FILES" -gt 0 && "$IN_TESTS" -eq 0 && "$PHASE" == "red" ]]; then
    deny "BLOCKED: RED phase -- only test files editable. Write failing tests first." \
         "RED phase -- only test files editable. Write failing tests, then run: bash $CTL next. To bypass once: bash $CTL skip --reason \"...\""
  fi

  # GREEN phase: only impl files editable
  if [[ "$IN_TESTS" -gt 0 && "$PHASE" == "green" ]]; then
    deny "BLOCKED: GREEN phase -- only impl files editable. Make tests pass." \
         "GREEN phase -- only impl files editable. Make tests pass, then run: bash $CTL next. If tests are wrong: bash $CTL back. To bypass once: bash $CTL skip --reason \"...\""
  fi

  allow
fi

# ─── Shell Commands (beforeShellExecution) ───────────────────────────────────

if [[ "$IS_SHELL" == "true" ]]; then

  COMMAND=$(printf '%s' "$INPUT" | jq -r '.command // empty' 2>/dev/null || true)

  # Whitelist devblock-ctl calls
  if printf '%s' "$COMMAND" | grep -qE 'devblock-ctl\.(sh|ps1)'; then
    allow
  fi

  # No active feature → allow all shell
  if [[ -z "$CURRENT" || "$CURRENT" == "null" ]]; then
    allow
  fi

  # Whitelist readonly commands
  if printf '%s' "$COMMAND" | grep -qE '^\s*(ls|cat|echo|find|which|file|stat|du|df|wc|head|tail|pwd|date|env)\s'; then
    allow
  fi

  # Block file-modifying patterns
  if printf '%s' "$COMMAND" | grep -qE '([^2]>\s*[^&/]|[^0-9]>>\s*[^/]|sed\s+-i|tee\s+|rm\s+|mv\s+|cp\s+)'; then
    # Whitelist test runners and git
    if printf '%s' "$COMMAND" | grep -qE '^\s*(git\s+|npm\s+test|npx\s+|yarn\s+test|pnpm\s+test|pytest|python\s+-m\s+pytest|cargo\s+test|go\s+test|make\s+test|bundle\s+exec\s+rspec|jest|vitest|mocha|bun\s+test)'; then
      allow
    fi
    # Whitelist piping to read-only commands
    if printf '%s' "$COMMAND" | grep -qE '\|\s*(grep|head|tail|less|wc|sort|cat|jq|awk|sed\s+[^-])' && ! printf '%s' "$COMMAND" | grep -qE '([^2]>\s*[^&/]|[^0-9]>>\s*[^/])'; then
      allow
    fi
    deny "BLOCKED: Do not modify files via shell. Use the Write tool instead -- it is scope-checked." \
         "Do not modify files via shell. Use the Write tool instead -- it is scope-checked by DevBlock."
  fi

  allow
fi

# ─── Default: allow unknown hook types ───────────────────────────────────────

allow
