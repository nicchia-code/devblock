#!/usr/bin/env bash
# pre-compact.sh — preCompact hook for DevBlock (Cursor)
# Preserves TDD state across context compaction.
# Installed at: ~/.cursor/hooks/devblock/pre-compact.sh
set -o pipefail

PROJECT_DIR="${CURSOR_PROJECT_DIR:-.}"
SCOPE_FILE="$PROJECT_DIR/.scope.json"
CTL="~/.cursor/hooks/devblock/devblock-ctl.sh"

if [[ -f "$SCOPE_FILE" ]] && command -v jq &>/dev/null; then
  state=$(jq -c '{
    feature: .current.name,
    phase: .current.phase,
    files: .current.files,
    tests: .current.tests,
    queue_len: (.queue | length),
    completed_len: (.completed | length)
  }' "$SCOPE_FILE" 2>/dev/null)

  if [[ -n "$state" && "$state" != "null" ]]; then
    state_escaped=$(printf '%s' "$state" | sed 's/"/\\"/g')
    cat <<EOJSON
{"agent_message":"DEVBLOCK STATE (preserve across compaction): $state_escaped. Commands: next=bash $CTL next, back=bash $CTL back, scope-add=bash $CTL scope-add <file>, skip=bash $CTL skip --reason '...', stop=bash $CTL stop."}
EOJSON
  fi
fi

exit 0
