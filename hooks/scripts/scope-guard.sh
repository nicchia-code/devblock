#!/usr/bin/env bash
# scope-guard.sh — PreToolUse hook for DevBlock
# Enforces scope locking and 8-phase TDD constraints.
# Reads tool input from stdin (JSON), outputs JSON response.
set -o pipefail
trap 'echo "scope-guard.sh: error at line $LINENO (exit=$?)" >&2' ERR

SCOPE_FILE=".scope.json"

# ─── Helpers ─────────────────────────────────────────────────────────────────

allow() {
  exit 0
}

deny() {
  local reason="$1"
  reason=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
  cat <<EOJSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"$reason"}}
EOJSON
  exit 0
}

# ─── Read hook input ─────────────────────────────────────────────────────────

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)

# ─── Rule 0: No .scope.json → no session, allow everything ──────────────────

if [[ ! -f "$SCOPE_FILE" ]]; then
  allow
fi

# ─── Check jq availability ──────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "⚠️  WARNING: jq not found. DevBlock scope guard disabled." >&2
  allow
fi

# ─── Load session state ─────────────────────────────────────────────────────

CURRENT=$(jq -r '.current // empty' "$SCOPE_FILE" 2>/dev/null || true)
PHASE=$(jq -r '.current.phase // empty' "$SCOPE_FILE" 2>/dev/null || true)

# ─── Pre-extract tool_input fields ──────────────────────────────────────────

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

# ─── Handle Edit/Write/MultiEdit ─────────────────────────────────────────────

if [[ "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "MultiEdit" ]]; then

  # Normalize: strip project dir prefix if present
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    FILE_PATH="${FILE_PATH#$CLAUDE_PROJECT_DIR/}"
  fi
  # Also strip leading ./
  FILE_PATH="${FILE_PATH#./}"

  # Rule 1: .scope.json is ALWAYS blocked for Edit/Write
  if [[ "$FILE_PATH" == ".scope.json" || "$FILE_PATH" == *"/.scope.json" ]]; then
    deny "🚫 .scope.json cannot be edited directly. State changes go through devblock-ctl.sh (use /devblock:phase, /devblock:next, etc.)"
  fi

  # Rule 1b: Files outside the project directory are not our concern
  if [[ "$FILE_PATH" == /* ]]; then
    allow
  fi

  # Rule 2: No current feature active
  if [[ -z "$CURRENT" || "$CURRENT" == "null" ]]; then
    deny "🚫 No active feature. Start from a plan or use /devblock:next."
  fi

  # Check if file is in scope
  IN_FILES=$(jq --arg f "$FILE_PATH" '.current.files // [] | map(select(. == $f)) | length' "$SCOPE_FILE" 2>/dev/null || echo "0")
  IN_TESTS=$(jq --arg f "$FILE_PATH" '.current.tests // [] | map(select(. == $f)) | length' "$SCOPE_FILE" 2>/dev/null || echo "0")

  # Rule 3: File not in scope at all
  if [[ "$IN_FILES" -eq 0 && "$IN_TESTS" -eq 0 ]]; then
    SCOPE_LIST=$(jq -r '[(.current.files // [])[], (.current.tests // [])[]] | join(", ")' "$SCOPE_FILE" 2>/dev/null || echo "(unable to read)")
    deny "🚫 File '$FILE_PATH' is outside the current scope. Declared files: $SCOPE_LIST. Use /devblock:scope-add to add it."
  fi

  # Rule 4: Phase-based file locking (8 phases)
  case "$PHASE" in
    gather|run|retest|review|done)
      deny "🚫 No file editing in $PHASE phase. Files are read-only."
      ;;
    test|fix-tests)
      if [[ "$IN_TESTS" -eq 0 ]]; then
        deny "🚫 Only test files are editable in $PHASE phase. '$FILE_PATH' is an implementation file."
      fi
      ;;
    implement)
      if [[ "$IN_FILES" -eq 0 ]]; then
        deny "🚫 Only implementation files are editable in implement phase. '$FILE_PATH' is a test file."
      fi
      ;;
    *)
      deny "🚫 Unknown phase '$PHASE'. Cannot determine file permissions."
      ;;
  esac

  # All checks passed
  allow
fi

# ─── Handle Bash ─────────────────────────────────────────────────────────────

if [[ "$TOOL_NAME" == "Bash" ]]; then
  # devblock-ctl.sh always allowed
  if printf '%s' "$COMMAND" | grep -qE 'devblock-ctl\.sh[[:space:]]'; then
    allow
  fi

  # If no active session, allow all bash commands
  if [[ -z "$CURRENT" || "$CURRENT" == "null" ]]; then
    allow
  fi

  # Block only patterns that write files
  # Pure ERE — no \b or \s (GNU extensions), portable across GNU/BSD grep
  if printf '%s' "$COMMAND" | grep -qE '[^2&]>[[:space:]]*[^&/[:space:]]|[^0-9]>>[[:space:]]|sed[[:space:]]+-i|tee[[:space:]]+[^-]|(^|[[:space:];|&])rm[[:space:]]|(^|[[:space:];|&])mv[[:space:]]|(^|[[:space:];|&])cp[[:space:]]'; then
    # Allow test runners
    if printf '%s' "$COMMAND" | grep -qE '^[[:space:]]*(npm[[:space:]]+test|npx|yarn[[:space:]]+test|pnpm[[:space:]]+test|pytest|python[[:space:]]+-m[[:space:]]+pytest|cargo[[:space:]]+test|go[[:space:]]+test|make[[:space:]]+test|bundle[[:space:]]+exec[[:space:]]+rspec|jest|vitest|mocha|bun[[:space:]]+test)'; then
      allow
    fi
    deny "🚫 File-modifying Bash commands are blocked during a DevBlock session. Use Edit/Write tools instead (they are scope-checked). Command: $(echo "$COMMAND" | head -c 100)"
  fi

  allow
fi

# ─── Default: allow unknown tools ───────────────────────────────────────────

allow
