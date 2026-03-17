#!/usr/bin/env bash
# plan-trigger.sh — PostToolUse hook for DevBlock
# Triggers after ExitPlanMode to suggest DevBlock workflow.
set -o pipefail

SCOPE_FILE=".scope.json"

# If .scope.json already exists, don't interfere with active session
if [[ -f "$SCOPE_FILE" ]]; then
  exit 0
fi

# If .devblock/ doesn't exist, plugin not installed — skip
if [[ ! -d ".devblock" ]]; then
  exit 0
fi

# Inject message into Claude's context
cat <<'EOJSON'
{"hookSpecificOutput":{"hookEventName":"PostToolUse","message":"Piano approvato. DevBlock e' disponibile. Chiedi all'utente: 'Vuoi sviluppare con DevBlock?' Se si': leggi il piano, estrai feature/file/test/test_command, mostra una TABELLA di riepilogo, chiedi conferma, poi esegui: bash .devblock/devblock-ctl.sh init '{\"current\":{\"name\":\"...\",\"phase\":\"gather\",\"files\":[...],\"tests\":[...],\"test_command\":\"...\"},\"queue\":[...]}' — il JSON va passato come singolo argomento stringa. Vedi CLAUDE.md sezione 'Formato JSON per devblock-ctl.sh init' per i dettagli."}}
EOJSON
