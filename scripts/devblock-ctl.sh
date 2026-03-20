#!/usr/bin/env bash
# devblock-ctl.sh — Single writer of .scope.json
# Commands: install, init, status, next, back, scope-add, skip, stop
set -euo pipefail

SCOPE_FILE=".scope.json"

# ─── Helpers ─────────────────────────────────────────────────────────────────

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "$*"; }
ok() { echo "$*"; }

require_jq() {
  command -v jq &>/dev/null || die "jq is not installed. Install it with: sudo apt install jq (or brew install jq)."
}

require_scope() {
  [[ -f "$SCOPE_FILE" ]] || die "No active session. Call /devblock:start to begin."
}

require_current() {
  require_scope
  local current
  current=$(jq -r '.current' "$SCOPE_FILE")
  [[ "$current" != "null" && -n "$current" ]] || die "No active feature. Call /devblock:start to begin."
}

get_phase() {
  jq -r '.current.phase' "$SCOPE_FILE"
}

get_test_command() {
  jq -r '.current.test_command' "$SCOPE_FILE"
}

run_tests() {
  local test_cmd
  test_cmd=$(get_test_command)
  [[ "$test_cmd" != "null" && -n "$test_cmd" ]] || die "No test_command configured. Call /devblock:stop, then /devblock:start and provide a test command."
  info "Running tests: $test_cmd"
  local exit_code=0
  ( eval "$test_cmd" ) 2>&1 || exit_code=$?
  return $exit_code
}

auto_commit() {
  local feature_name="$1"
  # Stage only scoped files (impl + tests)
  local files
  files=$(jq -r '[(.current.files // [])[], (.current.tests // [])[]] | .[]' "$SCOPE_FILE" 2>/dev/null)
  if [[ -z "$files" ]]; then
    info "No files to commit."
    return 0
  fi
  local staged=0
  while IFS= read -r f; do
    if [[ -f "$f" ]] && git diff --name-only -- "$f" 2>/dev/null | grep -q . || git ls-files --others --exclude-standard -- "$f" 2>/dev/null | grep -q .; then
      git add "$f" 2>/dev/null && ((staged++)) || true
    fi
  done <<< "$files"
  if [[ "$staged" -gt 0 ]]; then
    git commit -m "feat: $feature_name" 2>/dev/null && ok "Auto-committed: $feature_name" || info "Nothing to commit."
  else
    info "No changes to commit."
  fi
}

# ─── Commands ────────────────────────────────────────────────────────────────

cmd_install() {
  require_jq
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  local plugin_dir
  plugin_dir="$(cd "$script_dir/.." && pwd)"

  local src_guard="$plugin_dir/hooks/scripts/scope-guard.sh"
  local src_ctl="$plugin_dir/scripts/devblock-ctl.sh"

  [[ -f "$src_guard" ]] || die "Cannot find scope-guard.sh at $src_guard"
  [[ -f "$src_ctl" ]] || die "Cannot find devblock-ctl.sh at $src_ctl"

  mkdir -p .devblock
  cp "$src_guard" .devblock/scope-guard.sh
  cp "$src_ctl" .devblock/devblock-ctl.sh
  chmod +x .devblock/scope-guard.sh .devblock/devblock-ctl.sh

  if [[ -f .gitignore ]]; then
    grep -q '\.devblock' .gitignore 2>/dev/null || echo '.devblock/' >> .gitignore
    grep -q '\.scope\.json' .gitignore 2>/dev/null || echo '.scope.json' >> .gitignore
  else
    printf '.devblock/\n.scope.json\n' > .gitignore
  fi

  ok "DevBlock installed to .devblock/"
}

cmd_init() {
  local json="$1"
  require_jq

  echo "$json" | jq empty 2>/dev/null || die "Invalid JSON. Fix the JSON syntax and call /devblock:start again."

  local name phase files tests test_command
  name=$(echo "$json" | jq -r '.current.name // empty')
  phase=$(echo "$json" | jq -r '.current.phase // empty')
  files=$(echo "$json" | jq -r '.current.files // empty')
  tests=$(echo "$json" | jq -r '.current.tests // empty')
  test_command=$(echo "$json" | jq -r '.current.test_command // empty')

  [[ -n "$name" ]] || die "Missing current.name. Call /devblock:start and provide a feature name."
  [[ -n "$phase" ]] || die "Missing current.phase. Set phase to 'red' in the JSON."
  [[ -n "$files" ]] || die "Missing current.files. Call /devblock:start and provide implementation file paths."
  [[ -n "$tests" ]] || die "Missing current.tests. Call /devblock:start and provide test file paths."
  [[ -n "$test_command" ]] || die "Missing current.test_command. Call /devblock:start and provide a test command."

  local enriched
  enriched=$(echo "$json" | jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .session //= $ts |
    .current.started_at //= $ts |
    .queue //= [] |
    .completed //= []
  ')

  echo "$enriched" > "$SCOPE_FILE"
  ok "Session started: $name (RED phase)"
  info "Write failing tests, then call /devblock:next."
}

cmd_status() {
  require_jq
  if [[ ! -f "$SCOPE_FILE" ]]; then
    info "No active session."
    exit 0
  fi
  jq '.' "$SCOPE_FILE"
}

cmd_next() {
  require_jq
  require_current

  local phase
  phase=$(get_phase)

  case "$phase" in
    red)
      info "Validating: tests must FAIL in RED phase..."
      if run_tests; then
        die "Tests are PASSING. Write failing tests first, then call /devblock:next."
      fi
      ok "Tests correctly failing. Moving to GREEN phase."
      jq '.current.phase = "green"' "$SCOPE_FILE" > "${SCOPE_FILE}.tmp" && mv "${SCOPE_FILE}.tmp" "$SCOPE_FILE"
      info "GREEN phase. Make tests pass, then call /devblock:next."
      ;;
    green)
      info "Validating: tests must PASS in GREEN phase..."
      if ! run_tests; then
        die "Tests still FAILING. Fix implementation, then call /devblock:next."
      fi
      ok "Tests passing. Feature complete!"

      # Auto-commit scoped files
      local feature_name
      feature_name=$(jq -r '.current.name' "$SCOPE_FILE")
      auto_commit "$feature_name"

      # Move current to completed
      local now
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      jq --arg ts "$now" '
        .completed += [.current + {phase: "done", completed_at: $ts}] |
        .current = null
      ' "$SCOPE_FILE" > "${SCOPE_FILE}.tmp" && mv "${SCOPE_FILE}.tmp" "$SCOPE_FILE"

      # Pop next from queue
      local queue_len
      queue_len=$(jq '.queue | length' "$SCOPE_FILE")
      if [[ "$queue_len" -gt 0 ]]; then
        local next_name
        jq --arg ts "$now" '
          .current = .queue[0] + {phase: "red", started_at: $ts} |
          .queue = .queue[1:]
        ' "$SCOPE_FILE" > "${SCOPE_FILE}.tmp" && mv "${SCOPE_FILE}.tmp" "$SCOPE_FILE"
        next_name=$(jq -r '.current.name' "$SCOPE_FILE")
        ok "RED phase for: $next_name"
        info "Write failing tests, then call /devblock:next."
        info "Remaining in queue: $((queue_len - 1))"
      else
        ok "All features completed!"
      fi
      ;;
    *)
      die "Unexpected phase '$phase'. Run: bash .devblock/devblock-ctl.sh status to check state."
      ;;
  esac
}

cmd_back() {
  require_jq
  require_current

  local phase
  phase=$(get_phase)

  if [[ "$phase" != "green" ]]; then
    die "Already in $phase phase. 'back' only works from GREEN. You are in $phase — continue working, then call /devblock:next."
  fi

  jq '.current.phase = "red"' "$SCOPE_FILE" > "${SCOPE_FILE}.tmp" && mv "${SCOPE_FILE}.tmp" "$SCOPE_FILE"
  ok "Back to RED phase. Fix your tests, then call /devblock:next."
}

cmd_scope_add() {
  local file="${1:-}"
  local is_test=false
  require_jq
  require_current

  [[ -n "$file" ]] || die "Provide a file path. Usage: bash .devblock/devblock-ctl.sh scope-add <file> [--test]"

  if [[ "${2:-}" == "--test" ]]; then
    is_test=true
  fi

  [[ "$file" != ".scope.json" && "$file" != *"/.scope.json" ]] || die "Do not add .scope.json to scope. Choose your implementation or test files instead."

  local target_array
  if $is_test; then
    target_array="tests"
  else
    target_array="files"
  fi

  local already_exists
  already_exists=$(jq --arg f "$file" --arg arr "$target_array" '
    .current[$arr] | map(select(. == $f)) | length
  ' "$SCOPE_FILE")

  [[ "$already_exists" -eq 0 ]] || die "$file is already in scope ($target_array). No action needed — proceed with your current task."

  jq --arg f "$file" --arg arr "$target_array" '
    .current[$arr] += [$f]
  ' "$SCOPE_FILE" > "${SCOPE_FILE}.tmp" && mv "${SCOPE_FILE}.tmp" "$SCOPE_FILE"

  ok "Added $file to $target_array scope."
}

cmd_skip() {
  require_jq
  local reason=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason) reason="$2"; shift 2 ;;
      *) die "Unknown flag: $1" ;;
    esac
  done
  [[ -z "$reason" ]] && die "Usage: devblock-ctl.sh skip --reason \"...\""
  [[ ! -f "$SCOPE_FILE" ]] && die "No active session."

  # Write single-use skip token
  echo "{\"reason\":$(printf '%s' "$reason" | jq -Rs .),\"created_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > .devblock/.skip-token

  # Append to skip log
  local phase
  phase=$(jq -r '.current.phase // "none"' "$SCOPE_FILE")
  local feature
  feature=$(jq -r '.current.name // "none"' "$SCOPE_FILE")
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | phase=$phase | feature=$feature | reason: $reason" >> .devblock/skips.log

  echo "Skip token created. You may now make ONE edit outside the current phase."
  echo "Reason logged: $reason"
}

cmd_stop() {
  local full="${1:-}"
  require_jq

  if [[ ! -f "$SCOPE_FILE" ]]; then
    echo '{"ok":false,"error":"No active session."}'
    exit 1
  fi

  local current_name phase queue_len
  current_name=$(jq -r '.current.name // "none"' "$SCOPE_FILE" 2>/dev/null)
  phase=$(jq -r '.current.phase // "none"' "$SCOPE_FILE" 2>/dev/null)
  queue_len=$(jq -r '.queue | length' "$SCOPE_FILE" 2>/dev/null || echo "0")

  rm -f "$SCOPE_FILE"

  local msg="Session closed. Feature: $current_name (phase: $phase), queue: $queue_len remaining."

  if [[ "$full" == "--full" ]]; then
    rm -rf .devblock
    if [[ -f .gitignore ]]; then
      sed -i '/^\.devblock\/$/d' .gitignore
      sed -i '/^\.scope\.json$/d' .gitignore
    fi
    msg="$msg Uninstalled .devblock/ directory."
  fi

  echo "{\"ok\":true,\"message\":\"$msg\"}"
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    install)   cmd_install ;;
    init)      cmd_init "$*" ;;
    status)    cmd_status ;;
    next)      cmd_next ;;
    back)      cmd_back ;;
    scope-add) cmd_scope_add "$@" ;;
    skip)      cmd_skip "$@" ;;
    stop)      cmd_stop "$@" ;;
    *)         die "Unknown command '$cmd'. Use one of: install, init, status, next, back, scope-add, skip, stop." ;;
  esac
}

main "$@"
