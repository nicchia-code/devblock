#!/usr/bin/env bash
# session-start.sh — sessionStart hook for DevBlock (Cursor)
# Injects TDD rules and active session state into agent context.
# Installed at: ~/.cursor/hooks/devblock/session-start.sh
set -o pipefail

PROJECT_DIR="${CURSOR_PROJECT_DIR:-.}"
SCOPE_FILE="$PROJECT_DIR/.scope.json"
CTL="~/.cursor/hooks/devblock/devblock-ctl.sh"

# Always inject the base rules
RULES="DevBlock TDD Enforcement is active."
RULES="$RULES Rules: (1) RED phase: only test files writable. (2) GREEN phase: only impl files writable."
RULES="$RULES (3) Files must be in scope. (4) Never edit .scope.json directly."
RULES="$RULES (5) File-modifying shell is blocked; use Write tool. (6) Skip requires reason + user confirmation, single-use."
RULES="$RULES (7) Never skip without genuine need."
RULES="$RULES Commands: init=bash $CTL init '<JSON>', status=bash $CTL status, next=bash $CTL next,"
RULES="$RULES back=bash $CTL back, scope-add=bash $CTL scope-add <file> [--test],"
RULES="$RULES skip=bash $CTL skip --reason '...', stop=bash $CTL stop [--full]."
RULES="$RULES Workflow: ask user for feature name+files+tests+test_command, build JSON, run init, write failing tests (RED),"
RULES="$RULES run next (validates tests fail, moves to GREEN), implement (GREEN), run next (validates tests pass, auto-commits)."
RULES="$RULES Stop is user-only. Never stop autonomously."

# If active session, append current state
if [[ -f "$SCOPE_FILE" ]] && command -v jq &>/dev/null; then
  name=$(jq -r '.current.name // empty' "$SCOPE_FILE" 2>/dev/null)
  phase=$(jq -r '.current.phase // empty' "$SCOPE_FILE" 2>/dev/null)

  if [[ -n "$name" && -n "$phase" ]]; then
    files=$(jq -r '.current.files // [] | join(", ")' "$SCOPE_FILE" 2>/dev/null)
    tests=$(jq -r '.current.tests // [] | join(", ")' "$SCOPE_FILE" 2>/dev/null)
    queue_len=$(jq -r '.queue | length' "$SCOPE_FILE" 2>/dev/null || echo "0")
    RULES="$RULES ACTIVE SESSION: feature='$name', phase=$phase, impl=[$files], tests=[$tests], queue=$queue_len."
  fi
fi

# Escape for JSON
RULES=$(printf '%s' "$RULES" | sed 's/"/\\"/g' | tr '\n' ' ')

echo "{\"agent_message\":\"$RULES\"}"
exit 0
