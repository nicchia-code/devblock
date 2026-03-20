#!/usr/bin/env bash
# scope-guard.sh — PreToolUse hook for DevBlock v4
# Enforces scope locking and RED/GREEN phase constraints.
set -o pipefail

SCOPE_FILE=".scope.json"

# ─── Helpers ─────────────────────────────────────────────────────────────────

allow() { exit 0; }

deny() {
  local reason="$1"
  reason=$(printf '%s' "$reason" | sed 's/"/\\"/g' | tr '\n' ' ')
  cat <<EOJSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"$reason"}}
EOJSON
  exit 0
}

# ─── Read hook input ─────────────────────────────────────────────────────────

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)

# ─── No session → allow everything ───────────────────────────────────────────

[[ -f "$SCOPE_FILE" ]] || allow
command -v jq &>/dev/null || allow

# ─── Load state ──────────────────────────────────────────────────────────────

CURRENT=$(jq -r '.current // empty' "$SCOPE_FILE" 2>/dev/null || true)
PHASE=$(jq -r '.current.phase // empty' "$SCOPE_FILE" 2>/dev/null || true)

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

# ─── Edit/Write/MultiEdit ───────────────────────────────────────────────────

if [[ "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "MultiEdit" ]]; then

  # Normalize path
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    FILE_PATH="${FILE_PATH#$CLAUDE_PROJECT_DIR/}"
  fi
  FILE_PATH="${FILE_PATH#./}"

  # Block .scope.json edits
  if [[ "$FILE_PATH" == ".scope.json" || "$FILE_PATH" == *"/.scope.json" ]]; then
    deny "BLOCKED: Do not edit .scope.json. To advance phase, call /devblock:next. To add files, call /devblock:add <file>."
  fi

  # Files outside project are not our concern
  [[ "$FILE_PATH" != /* ]] || allow

  # No active feature
  if [[ -z "$CURRENT" || "$CURRENT" == "null" ]]; then
    deny "BLOCKED: No active feature. Call /devblock:start to begin."
  fi

  # Check scope membership
  IN_FILES=$(jq --arg f "$FILE_PATH" '.current.files // [] | map(select(. == $f)) | length' "$SCOPE_FILE" 2>/dev/null || echo "0")
  IN_TESTS=$(jq --arg f "$FILE_PATH" '.current.tests // [] | map(select(. == $f)) | length' "$SCOPE_FILE" 2>/dev/null || echo "0")

  # File not in scope
  if [[ "$IN_FILES" -eq 0 && "$IN_TESTS" -eq 0 ]]; then
    SCOPE_LIST=$(jq -r '[(.current.files // [])[], (.current.tests // [])[]] | join(", ")' "$SCOPE_FILE" 2>/dev/null || echo "(unknown)")
    deny "BLOCKED: '$FILE_PATH' not in scope. Files: $SCOPE_LIST. Call /devblock:add $FILE_PATH."
  fi

  # --- Skip token: single-use phase bypass ---
  if [[ -f .devblock/.skip-token ]]; then
    rm -f .devblock/.skip-token
    allow
  fi

  # RED phase: only test files editable
  if [[ "$IN_FILES" -gt 0 && "$IN_TESTS" -eq 0 && "$PHASE" == "red" ]]; then
    deny "BLOCKED: RED phase — only test files editable. Write failing tests, then /devblock:next. If you must bypass, use /devblock:skip."
  fi

  # GREEN phase: only impl files editable
  if [[ "$IN_TESTS" -gt 0 && "$PHASE" == "green" ]]; then
    deny "BLOCKED: GREEN phase — only impl files editable. Make tests pass, then /devblock:next. If tests are wrong, run: bash .devblock/devblock-ctl.sh back. If you must bypass, use /devblock:skip."
  fi

  allow
fi

# ─── Bash ────────────────────────────────────────────────────────────────────

if [[ "$TOOL_NAME" == "Bash" ]]; then

  # Whitelist devblock-ctl.sh calls
  if printf '%s' "$COMMAND" | grep -qE 'devblock-ctl\.sh'; then
    allow
  fi

  # No active feature → allow all bash
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
    deny "BLOCKED: Do not modify files via Bash. Use the Edit or Write tool instead — they are scope-checked."
  fi

  allow
fi

# ─── Default: allow unknown tools ───────────────────────────────────────────

allow
