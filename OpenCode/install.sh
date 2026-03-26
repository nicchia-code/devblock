#!/bin/sh
# install.sh — Install / uninstall DevBlock for OpenCode (Linux/Mac/WSL)
# Usage: sh install.sh [--uninstall | --status | --help]
set -eu

DEVBLOCK_VERSION="5.0.0"

# ─── Helpers ─────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.config/opencode"

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

die()  { printf "${RED}ERROR: %s${RESET}\n" "$*" >&2; exit 1; }
ok()   { printf "  ${GREEN}OK${RESET}: %s\n" "$*"; }
warn() { printf "  ${YELLOW}WARN${RESET}: %s\n" "$*"; }
info() { printf "  ${CYAN}INFO${RESET}: %s\n" "$*"; }
step() { printf "\n${BOLD}[%s] %s${RESET}\n" "$1" "$2"; }

# ─── File list ───────────────────────────────────────────────────────────────
# All files DevBlock installs, relative to $DEST.

devblock_file_list() {
  cat <<'EOF'
plugins/devblock.ts
agents/tdd.md
agents/tdd-auto.md
commands/tdd-status.md
skills/devblock-start/SKILL.md
skills/devblock-next/SKILL.md
skills/devblock-add/SKILL.md
skills/devblock-skip/SKILL.md
skills/devblock-stop/SKILL.md
EOF
}

# ─── AGENTS.md helpers ───────────────────────────────────────────────────────

SENTINEL_BEGIN="<!-- BEGIN DEVBLOCK -->"
SENTINEL_END="<!-- END DEVBLOCK -->"

agents_md_has_devblock() {
  [ -f "$DEST/AGENTS.md" ] && grep -q "$SENTINEL_BEGIN" "$DEST/AGENTS.md" 2>/dev/null
}

agents_md_inject() {
  if [ -f "$DEST/AGENTS.md" ]; then
    if agents_md_has_devblock; then
      _before=$(sed "/$SENTINEL_BEGIN/,\$d" "$DEST/AGENTS.md")
      _after=$(sed "1,/$SENTINEL_END/d" "$DEST/AGENTS.md")
      { printf '%s\n' "$_before"; cat "$SCRIPT_DIR/AGENTS.md"; printf '%s\n' "$_after"; } > "$DEST/AGENTS.md.tmp"
      mv "$DEST/AGENTS.md.tmp" "$DEST/AGENTS.md"
      ok "AGENTS.md — replaced DevBlock section"
    else
      printf '\n' >> "$DEST/AGENTS.md"
      cat "$SCRIPT_DIR/AGENTS.md" >> "$DEST/AGENTS.md"
      ok "AGENTS.md — appended DevBlock section"
    fi
  else
    cp "$SCRIPT_DIR/AGENTS.md" "$DEST/AGENTS.md"
    ok "AGENTS.md — created"
  fi
}

agents_md_remove() {
  if [ -f "$DEST/AGENTS.md" ] && agents_md_has_devblock; then
    _before=$(sed "/$SENTINEL_BEGIN/,\$d" "$DEST/AGENTS.md")
    _after=$(sed "1,/$SENTINEL_END/d" "$DEST/AGENTS.md")
    { printf '%s' "$_before"; printf '%s' "$_after"; } > "$DEST/AGENTS.md.tmp"
    mv "$DEST/AGENTS.md.tmp" "$DEST/AGENTS.md"
    if [ ! -s "$DEST/AGENTS.md" ] || ! grep -q '[^ \t\n]' "$DEST/AGENTS.md" 2>/dev/null; then
      rm -f "$DEST/AGENTS.md"
      ok "AGENTS.md — removed (was empty)"
    else
      ok "AGENTS.md — removed DevBlock section"
    fi
  else
    info "AGENTS.md — no DevBlock section found"
  fi
}

# ─── Trap for partial installs ──────────────────────────────────────────────

_install_started=false
trap_handler() {
  if [ "$_install_started" = "true" ]; then
    printf "\n${RED}Installation failed — a partial install may exist at %s${RESET}\n" "$DEST" >&2
    printf "Run ${BOLD}sh %s --uninstall${RESET} to clean up.\n" "$0" >&2
  fi
}
trap trap_handler EXIT

# ─── Usage ───────────────────────────────────────────────────────────────────

show_help() {
  cat <<HELP
DevBlock installer for OpenCode v$DEVBLOCK_VERSION

Usage: sh $0 [OPTION]

Options:
  (none)        Install DevBlock
  --uninstall   Remove all DevBlock files
  --status      Show what is installed
  --help        Show this help message

Destination: $DEST
HELP
  exit 0
}

# ─── Status ──────────────────────────────────────────────────────────────────

show_status() {
  printf "${BOLD}DevBlock for OpenCode v%s${RESET}\n" "$DEVBLOCK_VERSION"
  printf "Config directory: %s\n\n" "$DEST"

  printf "Files:\n"
  _ok=0 _miss=0
  for f in $(devblock_file_list); do
    if [ -f "$DEST/$f" ]; then
      printf "  ${GREEN}+${RESET} %s\n" "$f"
      _ok=$((_ok + 1))
    else
      printf "  ${RED}!${RESET} %s (missing)\n" "$f"
      _miss=$((_miss + 1))
    fi
  done
  if agents_md_has_devblock; then
    printf "  ${GREEN}+${RESET} AGENTS.md (DevBlock section)\n"
  else
    printf "  ${RED}!${RESET} AGENTS.md (no DevBlock section)\n"
  fi

  printf "\n"
  if [ "$_miss" -eq 0 ]; then
    printf "${GREEN}All files installed.${RESET}\n"
  else
    printf "${YELLOW}%d file(s) missing.${RESET} Run ${BOLD}sh %s${RESET} to install.\n" "$_miss" "$0"
  fi
  exit 0
}

# ─── Uninstall ───────────────────────────────────────────────────────────────

do_uninstall() {
  printf "${BOLD}Uninstalling DevBlock from: %s${RESET}\n" "$DEST"

  _removed=0
  for f in $(devblock_file_list); do
    if [ -f "$DEST/$f" ]; then
      rm -f "$DEST/$f"
      ok "Removed $f"
      _removed=$((_removed + 1))
    fi
  done

  agents_md_remove

  # Clean up empty directories
  for d in agents commands skills/devblock-start skills/devblock-next skills/devblock-add skills/devblock-skip skills/devblock-stop plugins; do
    rmdir "$DEST/$d" 2>/dev/null || true
  done
  rmdir "$DEST/skills" 2>/dev/null || true

  printf "\n${GREEN}DevBlock uninstalled.${RESET} Removed %d file(s).\n" "$_removed"
  exit 0
}

# ─── Install ─────────────────────────────────────────────────────────────────

do_install() {
  # Validate source tree
  [ -f "$SCRIPT_DIR/plugins/devblock.ts" ] || die "Cannot find plugins/devblock.ts — run from the DevBlock source directory"
  [ -d "$SCRIPT_DIR/agents" ]              || die "Cannot find agents/ directory"
  [ -d "$SCRIPT_DIR/skills" ]              || die "Cannot find skills/ directory"
  [ -d "$SCRIPT_DIR/commands" ]            || die "Cannot find commands/ directory"
  [ -f "$SCRIPT_DIR/AGENTS.md" ]           || die "Cannot find AGENTS.md"

  # Check destination is writable
  mkdir -p "$DEST" 2>/dev/null || die "Cannot create $DEST — check permissions"
  [ -w "$DEST" ] || die "$DEST is not writable"

  printf "${BOLD}Installing DevBlock v%s${RESET}\n" "$DEVBLOCK_VERSION"
  printf "Destination: %s\n" "$DEST"

  _install_started=true

  # ── 1. Plugin ──────────────────────────────────────────────────────────────

  step "1/5" "Plugin"
  mkdir -p "$DEST/plugins"
  cp "$SCRIPT_DIR/plugins/devblock.ts" "$DEST/plugins/devblock.ts"
  ok "devblock.ts"

  # ── 2. Agents ──────────────────────────────────────────────────────────────

  step "2/5" "Agents"
  mkdir -p "$DEST/agents"
  for agent_file in "$SCRIPT_DIR"/agents/*.md; do
    _name="$(basename "$agent_file")"
    cp "$agent_file" "$DEST/agents/$_name"
    ok "$_name"
  done

  # ── 3. Skills ──────────────────────────────────────────────────────────────

  step "3/5" "Skills"
  for skill_dir in "$SCRIPT_DIR"/skills/*/; do
    _name="$(basename "$skill_dir")"
    _dest_skill="$DEST/skills/$_name"
    mkdir -p "$_dest_skill"
    cp -R "$skill_dir"* "$_dest_skill/"
    ok "$_name"
  done

  # ── 4. Commands ────────────────────────────────────────────────────────────

  step "4/5" "Commands"
  mkdir -p "$DEST/commands"
  for cmd_file in "$SCRIPT_DIR"/commands/*.md; do
    _name="$(basename "$cmd_file")"
    cp "$cmd_file" "$DEST/commands/$_name"
    ok "$_name"
  done

  # ── 5. AGENTS.md ───────────────────────────────────────────────────────────

  step "5/5" "Global rules (AGENTS.md)"
  agents_md_inject

  _install_started=false

  # Post-install verification
  _ok=0 _miss=0
  for f in $(devblock_file_list); do
    if [ -f "$DEST/$f" ]; then
      _ok=$((_ok + 1))
    else
      warn "Missing after install: $f"
      _miss=$((_miss + 1))
    fi
  done

  # ── Summary ────────────────────────────────────────────────────────────────

  printf "\n${GREEN}${BOLD}DevBlock v%s installed successfully!${RESET}\n" "$DEVBLOCK_VERSION"
  printf "\n"
  printf "  Plugin:   1\n"
  printf "  Agents:   2 (TDD, TDD-Auto)\n"
  printf "  Skills:   5\n"
  printf "  Commands: 1 (/tdd-status)\n"
  printf "  Rules:    AGENTS.md\n"
  printf "  Verified: %d/%d files OK\n" "$_ok" "$((_ok + _miss))"
  printf "\n"
  printf "How to use:\n"
  printf "  1. Open any project with OpenCode\n"
  printf "  2. Press ${BOLD}Tab${RESET} to switch to the ${BOLD}TDD${RESET} or ${BOLD}TDD-Auto${RESET} agent\n"
  printf "  3. The plugin enforces RED/GREEN phases automatically\n"
  printf "\n"
  printf "Other commands:\n"
  printf "  sh %s --status      Show what is installed\n" "$0"
  printf "  sh %s --uninstall   Remove DevBlock completely\n" "$0"

  if [ "$_miss" -gt 0 ]; then
    printf "\n${YELLOW}Warning: %d file(s) missing after install — check the output above.${RESET}\n" "$_miss"
    exit 1
  fi
}

# ─── Main ────────────────────────────────────────────────────────────────────

case "${1:-}" in
  --help|-h)      show_help ;;
  --uninstall)    do_uninstall ;;
  --status)       show_status ;;
  "")             do_install ;;
  *)              die "Unknown option: $1 (try --help)" ;;
esac
