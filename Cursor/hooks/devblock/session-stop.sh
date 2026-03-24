#!/usr/bin/env bash
# session-stop.sh — stop hook for DevBlock (Cursor)
# Warns user if TDD session is still active when closing.
# Installed at: ~/.cursor/hooks/devblock/session-stop.sh
set -o pipefail

PROJECT_DIR="${CURSOR_PROJECT_DIR:-.}"
SCOPE_FILE="$PROJECT_DIR/.scope.json"

if [[ -f "$SCOPE_FILE" ]] && command -v jq &>/dev/null; then
  name=$(jq -r '.current.name // empty' "$SCOPE_FILE" 2>/dev/null)
  phase=$(jq -r '.current.phase // empty' "$SCOPE_FILE" 2>/dev/null)

  if [[ -n "$name" && -n "$phase" ]]; then
    cat <<EOJSON
{"user_message":"DevBlock: TDD session still active (feature: '$name', phase: $phase). It will resume automatically in your next session."}
EOJSON
  fi
fi

exit 0
