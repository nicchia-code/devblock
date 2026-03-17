#!/usr/bin/env bash
# devblock-ctl.sh — UNICO writer di .scope.json
# Claude lo invoca via Bash, ma questo script valida indipendentemente.
set -euo pipefail

SCOPE_FILE=".scope.json"

# ─── Helpers ─────────────────────────────────────────────────────────────────

die() { echo "❌ ERROR: $*" >&2; exit 1; }
info() { echo "ℹ️  $*"; }
ok() { echo "✅ $*"; }

require_jq() {
  command -v jq &>/dev/null || die "jq is required but not installed."
}

require_scope() {
  [[ -f "$SCOPE_FILE" ]] || die "No active session. Run /devblock:install and start from a plan."
}

require_current() {
  require_scope
  local current
  current=$(jq -r '.current' "$SCOPE_FILE")
  [[ "$current" != "null" && -n "$current" ]] || die "No active feature. Use /devblock:next or start from a plan."
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
  [[ "$test_cmd" != "null" && -n "$test_cmd" ]] || die "No test_command configured."
  info "Running tests: $test_cmd"
  local exit_code=0
  ( eval "$test_cmd" ) 2>&1 || exit_code=$?
  return $exit_code
}

# ─── Commands ────────────────────────────────────────────────────────────────

cmd_install() {
  require_jq
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  local plugin_dir
  plugin_dir="$(cd "$script_dir/.." && pwd)"

  local src_guard="$plugin_dir/hooks/scripts/scope-guard.sh"
  local src_trigger="$plugin_dir/hooks/scripts/plan-trigger.sh"
  local src_ctl="$plugin_dir/scripts/devblock-ctl.sh"

  [[ -f "$src_guard" ]] || die "Cannot find scope-guard.sh at $src_guard"
  [[ -f "$src_trigger" ]] || die "Cannot find plan-trigger.sh at $src_trigger"
  [[ -f "$src_ctl" ]] || die "Cannot find devblock-ctl.sh at $src_ctl"

  mkdir -p .devblock
  cp "$src_guard" .devblock/scope-guard.sh
  cp "$src_trigger" .devblock/plan-trigger.sh
  cp "$src_ctl" .devblock/devblock-ctl.sh
  chmod +x .devblock/scope-guard.sh .devblock/plan-trigger.sh .devblock/devblock-ctl.sh

  # Add .devblock/ to .gitignore if not already there
  if [[ -f .gitignore ]]; then
    grep -qx '\.devblock/' .gitignore 2>/dev/null || echo '.devblock/' >> .gitignore
    grep -qx '\.scope\.json' .gitignore 2>/dev/null || echo '.scope.json' >> .gitignore
  else
    printf '%s\n' '.devblock/' '.scope.json' > .gitignore
  fi

  ok "DevBlock installed to .devblock/"
  info "scope-guard.sh, plan-trigger.sh and devblock-ctl.sh copied from $plugin_dir"
}

cmd_init() {
  local json="$1"
  require_jq

  # Validate JSON structure
  echo "$json" | jq empty 2>/dev/null || die "Invalid JSON provided."

  # Validate required fields
  local name phase files tests test_command
  name=$(echo "$json" | jq -r '.current.name // empty')
  phase=$(echo "$json" | jq -r '.current.phase // empty')
  files=$(echo "$json" | jq -r '.current.files // empty')
  tests=$(echo "$json" | jq -r '.current.tests // empty')
  test_command=$(echo "$json" | jq -r '.current.test_command // empty')

  [[ -n "$name" ]] || die "current.name is required."
  [[ -n "$phase" ]] || die "current.phase is required."
  case "$phase" in
    gather|test|run|implement|retest|review|done) ;;
    *) die "Invalid phase '$phase'. Must be one of: gather, test, run, implement, retest, review, done." ;;
  esac
  [[ -n "$files" ]] || die "current.files is required."
  [[ -n "$tests" ]] || die "current.tests is required."
  [[ -n "$test_command" ]] || die "current.test_command is required."

  # Add session timestamp and started_at if not present
  local enriched
  enriched=$(echo "$json" | jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .session //= $ts |
    .current.started_at //= $ts |
    .queue //= [] |
    .completed //= [] |
    .config //= {}
  ')

  echo "$enriched" > "$SCOPE_FILE"
  ok "Session initialized: $name (phase: $phase)"
  echo "$enriched" | jq '.current | {name, phase, files: (.files | length), tests: (.tests | length)}'
}

cmd_status() {
  require_jq
  if [[ ! -f "$SCOPE_FILE" ]]; then
    info "No active session."
    exit 0
  fi
  jq '.' "$SCOPE_FILE"
}

cmd_phase() {
  local target="${1:-}"
  require_jq
  require_current

  local current_phase
  current_phase=$(get_phase)

  [[ -n "$target" ]] || die "Usage: devblock-ctl.sh phase <gather|test|run|implement|retest|review|done>"

  case "${current_phase}::${target}" in
    gather::test)
      ok "Moving to test phase."
      ;;
    test::run)
      ok "Moving to run phase."
      ;;
    run::implement)
      info "Validating: tests must FAIL before implementing..."
      if run_tests; then
        die "Tests are PASSING. In run phase, tests must FAIL before moving to implement. Write failing tests first."
      fi
      ok "Tests correctly failing. Moving to implement phase."
      ;;
    implement::retest)
      ok "Moving to retest phase."
      ;;
    retest::review)
      info "Validating: tests must PASS before review..."
      if ! run_tests; then
        die "Tests are FAILING. Make tests pass before moving to review."
      fi
      ok "Tests passing. Moving to review phase."
      ;;
    review::done)
      ok "Feature complete!"
      ;;
    review::gather)
      info "Review KO. Back to gather."
      ;;
    *::gather)
      info "Back to gather (user request)."
      ;;
    *::test)
      info "Back to test (user request)."
      ;;
    *)
      die "Invalid transition: $current_phase -> $target. Valid phases: gather, test, run, implement, retest, review, done."
      ;;
  esac

  if [[ "$target" == "done" ]]; then
    # Move current to completed, clear current
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg ts "$now" '
      .completed += [.current + {phase: "done", completed_at: $ts}] |
      .current = null
    ' "$SCOPE_FILE" > "${SCOPE_FILE}.tmp" && mv "${SCOPE_FILE}.tmp" "$SCOPE_FILE"
    ok "Feature moved to completed."
    info "Use /devblock:next to start the next feature."
  else
    jq --arg p "$target" '.current.phase = $p' "$SCOPE_FILE" > "${SCOPE_FILE}.tmp" && mv "${SCOPE_FILE}.tmp" "$SCOPE_FILE"
  fi
}

cmd_next() {
  require_jq
  require_scope

  local current
  current=$(jq -r '.current' "$SCOPE_FILE")

  # If there's a current feature that isn't done, validate tests pass
  if [[ "$current" != "null" ]]; then
    local phase
    phase=$(get_phase)
    if [[ "$phase" != "done" ]]; then
      info "Current feature not marked done. Validating tests pass..."
      if ! run_tests; then
        die "Tests are FAILING on current feature. Complete it before advancing."
      fi
      # Auto-mark as done
      local now
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      jq --arg ts "$now" '
        .completed += [.current + {phase: "done", completed_at: $ts}] |
        .current = null
      ' "$SCOPE_FILE" > "${SCOPE_FILE}.tmp" && mv "${SCOPE_FILE}.tmp" "$SCOPE_FILE"
      ok "Current feature auto-completed (tests passing)."
    fi
  fi

  # Check queue
  local queue_len
  queue_len=$(jq '.queue | length' "$SCOPE_FILE")

  if [[ "$queue_len" -eq 0 ]]; then
    info "🎉 Queue empty! All features completed."
    jq '.completed | length' "$SCOPE_FILE" | xargs -I{} echo "Total completed: {}"
    exit 0
  fi

  # Pop first from queue, set as current in gather phase
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq --arg ts "$now" '
    .current = .queue[0] + {phase: "gather", started_at: $ts} |
    .current.status = null |
    .queue = .queue[1:]
  ' "$SCOPE_FILE" > "${SCOPE_FILE}.tmp" && mv "${SCOPE_FILE}.tmp" "$SCOPE_FILE"

  # Clean up null status field
  jq 'if .current.status == null then del(.current.status) else . end' "$SCOPE_FILE" > "${SCOPE_FILE}.tmp" && mv "${SCOPE_FILE}.tmp" "$SCOPE_FILE"

  local new_name
  new_name=$(jq -r '.current.name' "$SCOPE_FILE")
  ok "Started: $new_name (phase: gather)"
  info "Remaining in queue: $((queue_len - 1))"
}

cmd_scope_add() {
  local file="${1:-}"
  local is_test=false
  require_jq
  require_current

  [[ -n "$file" ]] || die "Usage: devblock-ctl.sh scope-add <file> [--test]"

  # Check for --test flag
  if [[ "${2:-}" == "--test" ]]; then
    is_test=true
  fi

  # Hardcoded: .scope.json cannot be added to scope
  [[ "$file" != ".scope.json" ]] || die ".scope.json cannot be added to scope."
  [[ "$file" != *"/.scope.json" ]] || die ".scope.json cannot be added to scope."

  # Check for duplicates
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

  [[ "$already_exists" -eq 0 ]] || die "$file is already in scope ($target_array)."

  # Add to scope
  jq --arg f "$file" --arg arr "$target_array" '
    .current[$arr] += [$f]
  ' "$SCOPE_FILE" > "${SCOPE_FILE}.tmp" && mv "${SCOPE_FILE}.tmp" "$SCOPE_FILE"

  ok "Added $file to $target_array scope."
}

cmd_unfocus() {
  local full="${1:-}"
  require_jq

  if [[ ! -f "$SCOPE_FILE" ]]; then
    echo '{"ok":false,"error":"No active DevBlock session (.scope.json not found)"}'
    exit 1
  fi

  # Read state before deleting
  local current_name phase queue_len
  current_name=$(jq -r '.current.name // "none"' "$SCOPE_FILE" 2>/dev/null)
  phase=$(jq -r '.current.phase // "none"' "$SCOPE_FILE" 2>/dev/null)
  queue_len=$(jq -r '.queue | length' "$SCOPE_FILE" 2>/dev/null || echo "0")

  rm -f "$SCOPE_FILE"

  local msg="Session closed. Feature: $current_name (phase: $phase), queue: $queue_len remaining."

  if [[ "$full" == "--full" ]]; then
    rm -rf .devblock
    # Remove .devblock/ and .scope.json from .gitignore if present
    if [[ -f .gitignore ]]; then
      # Compatible with both GNU sed and macOS BSD sed
      sed -i.bak '/^\.devblock\/$/d' .gitignore && rm -f .gitignore.bak
      sed -i.bak '/^\.scope\.json$/d' .gitignore && rm -f .gitignore.bak
    fi
    msg="$msg Uninstalled .devblock/ directory."
  fi

  # Escape for safe JSON output
  msg=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')
  echo "{\"ok\":true,\"message\":\"$msg\"}"
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    install) cmd_install ;;
    init)    cmd_init "$*" ;;
    status)  cmd_status ;;
    phase)   cmd_phase "$@" ;;
    next)    cmd_next ;;
    scope-add) cmd_scope_add "$@" ;;
    unfocus)   cmd_unfocus "$@" ;;
    *)       die "Unknown command: $cmd. Available: install, init, status, phase, next, scope-add, unfocus" ;;
  esac
}

main "$@"
