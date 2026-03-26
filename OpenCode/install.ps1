# install.ps1 — Install / uninstall DevBlock for OpenCode (Windows / PowerShell 7)
# Usage: pwsh install.ps1 [-Uninstall] [-Status] [-Help]
param(
  [switch]$Uninstall,
  [switch]$Status,
  [switch]$Help
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$DevBlockVersion = '5.1.0'

# ─── Helpers ─────────────────────────────────────────────────────────────────

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Resolve-OpenCodeConfigDir {
  if ($env:APPDATA) {
    return Join-Path $env:APPDATA 'OpenCode'
  }
  return Join-Path $HOME '.config/opencode'
}

$Dest = Resolve-OpenCodeConfigDir

function Write-Ok   { param([string]$Msg) Write-Host "  " -NoNewline; Write-Host "OK" -ForegroundColor Green -NoNewline; Write-Host ": $Msg" }
function Write-Warn { param([string]$Msg) Write-Host "  " -NoNewline; Write-Host "WARN" -ForegroundColor Yellow -NoNewline; Write-Host ": $Msg" }
function Write-Inf  { param([string]$Msg) Write-Host "  " -NoNewline; Write-Host "INFO" -ForegroundColor Cyan -NoNewline; Write-Host ": $Msg" }
function Write-Err  { param([string]$Msg) Write-Host "ERROR: $Msg" -ForegroundColor Red; exit 1 }
function Write-Step { param([string]$Num, [string]$Msg) Write-Host "`n[$Num] $Msg" -ForegroundColor White }

# ─── File list ───────────────────────────────────────────────────────────────

function Get-DevBlockFileList {
  @(
    'plugins/devblock.ts'
    'agents/tdd.md'
    'agents/tdd-auto.md'
    'commands/tdd-status.md'
    'skills/devblock-start/SKILL.md'
    'skills/devblock-next/SKILL.md'
    'skills/devblock-add/SKILL.md'
    'skills/devblock-skip/SKILL.md'
    'skills/devblock-stop/SKILL.md'
  )
}

# ─── AGENTS.md helpers ───────────────────────────────────────────────────────

$SentinelBegin = '<!-- BEGIN DEVBLOCK -->'
$SentinelEnd   = '<!-- END DEVBLOCK -->'

function Test-AgentsMdHasDevBlock {
  $agentsFile = Join-Path $Dest 'AGENTS.md'
  if (Test-Path $agentsFile) {
    return (Get-Content $agentsFile -Raw) -match [regex]::Escape($SentinelBegin)
  }
  return $false
}

function Install-AgentsMdSection {
  $agentsFile = Join-Path $Dest 'AGENTS.md'
  $sourceContent = Get-Content (Join-Path $ScriptDir 'AGENTS.md') -Raw

  if (Test-Path $agentsFile) {
    if (Test-AgentsMdHasDevBlock) {
      $existing = Get-Content $agentsFile -Raw
      $pattern = "(?s)$([regex]::Escape($SentinelBegin)).*?$([regex]::Escape($SentinelEnd))"
      $replaced = $existing -replace $pattern, $sourceContent.TrimEnd()
      Set-Content -Path $agentsFile -Value $replaced -NoNewline
      Write-Ok 'AGENTS.md — replaced DevBlock section'
    } else {
      Add-Content -Path $agentsFile -Value "`n$sourceContent"
      Write-Ok 'AGENTS.md — appended DevBlock section'
    }
  } else {
    Copy-Item (Join-Path $ScriptDir 'AGENTS.md') $agentsFile -Force
    Write-Ok 'AGENTS.md — created'
  }
}

function Remove-AgentsMdSection {
  $agentsFile = Join-Path $Dest 'AGENTS.md'
  if ((Test-Path $agentsFile) -and (Test-AgentsMdHasDevBlock)) {
    $existing = Get-Content $agentsFile -Raw
    $pattern = "(?s)\r?\n?$([regex]::Escape($SentinelBegin)).*?$([regex]::Escape($SentinelEnd))\r?\n?"
    $cleaned = ($existing -replace $pattern, '').Trim()
    if ([string]::IsNullOrWhiteSpace($cleaned)) {
      Remove-Item $agentsFile -Force
      Write-Ok 'AGENTS.md — removed (was empty)'
    } else {
      Set-Content -Path $agentsFile -Value $cleaned -NoNewline
      Write-Ok 'AGENTS.md — removed DevBlock section'
    }
  } else {
    Write-Inf 'AGENTS.md — no DevBlock section found'
  }
}

# ─── Usage ───────────────────────────────────────────────────────────────────

function Show-Help {
  Write-Host @"
DevBlock installer for OpenCode v$DevBlockVersion

Usage: pwsh install.ps1 [OPTION]

Options:
  (none)        Install DevBlock
  -Uninstall    Remove all DevBlock files
  -Status       Show what is installed
  -Help         Show this help message

Destination: $Dest
"@
  exit 0
}

# ─── Status ──────────────────────────────────────────────────────────────────

function Show-Status {
  Write-Host "DevBlock for OpenCode v$DevBlockVersion" -ForegroundColor White
  Write-Host "Config directory: $Dest`n"

  Write-Host "Files:"
  $okCount = 0; $missCount = 0
  foreach ($f in (Get-DevBlockFileList)) {
    $fullPath = Join-Path $Dest $f
    if (Test-Path $fullPath) {
      Write-Host "  " -NoNewline; Write-Host "+" -ForegroundColor Green -NoNewline; Write-Host " $f"
      $okCount++
    } else {
      Write-Host "  " -NoNewline; Write-Host "!" -ForegroundColor Red -NoNewline; Write-Host " $f (missing)"
      $missCount++
    }
  }
  if (Test-AgentsMdHasDevBlock) {
    Write-Host "  " -NoNewline; Write-Host "!" -ForegroundColor Yellow -NoNewline; Write-Host " AGENTS.md (legacy DevBlock section — will be cleaned on next install)"
  }

  Write-Host ''
  if ($missCount -eq 0) {
    Write-Host "All files installed." -ForegroundColor Green
  } else {
    Write-Host "$missCount file(s) missing." -ForegroundColor Yellow -NoNewline
    Write-Host " Run pwsh install.ps1 to install."
  }
  exit 0
}

# ─── Uninstall ───────────────────────────────────────────────────────────────

function Start-Uninstall {
  Write-Host "Uninstalling DevBlock from: $Dest" -ForegroundColor White

  $removed = 0
  foreach ($f in (Get-DevBlockFileList)) {
    $fullPath = Join-Path $Dest $f
    if (Test-Path $fullPath) {
      Remove-Item $fullPath -Force
      Write-Ok "Removed $f"
      $removed++
    }
  }

  Remove-AgentsMdSection

  # Clean up empty directories
  foreach ($d in @('agents', 'commands', 'skills/devblock-start', 'skills/devblock-next', 'skills/devblock-add', 'skills/devblock-skip', 'skills/devblock-stop', 'plugins')) {
    $dirPath = Join-Path $Dest $d
    if ((Test-Path $dirPath) -and @(Get-ChildItem $dirPath -ErrorAction SilentlyContinue).Count -eq 0) {
      Remove-Item $dirPath -Force
    }
  }
  $skillsDir = Join-Path $Dest 'skills'
  if ((Test-Path $skillsDir) -and @(Get-ChildItem $skillsDir -ErrorAction SilentlyContinue).Count -eq 0) {
    Remove-Item $skillsDir -Force
  }

  Write-Host "`nDevBlock uninstalled." -ForegroundColor Green -NoNewline; Write-Host " Removed $removed file(s)."
  exit 0
}

# ─── Install ─────────────────────────────────────────────────────────────────

function Start-Install {
  # Validate source tree
  foreach ($check in @('plugins/devblock.ts', 'agents', 'skills', 'commands')) {
    if (-not (Test-Path (Join-Path $ScriptDir $check))) {
      Write-Err "Cannot find $check — run from the DevBlock source directory"
    }
  }

  # Check destination is writable
  try {
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
  } catch {
    Write-Err "Cannot create $Dest — check permissions"
  }

  Write-Host "Installing DevBlock v$DevBlockVersion" -ForegroundColor White
  Write-Host "Destination: $Dest"

  # ── 1. Plugin ──────────────────────────────────────────────────────────────

  Write-Step '1/5' 'Plugin'
  New-Item -ItemType Directory -Force -Path (Join-Path $Dest 'plugins') | Out-Null
  Copy-Item (Join-Path $ScriptDir 'plugins/devblock.ts') (Join-Path $Dest 'plugins/devblock.ts') -Force
  Write-Ok 'devblock.ts'

  # ── 2. Agents ──────────────────────────────────────────────────────────────

  Write-Step '2/5' 'Agents'
  New-Item -ItemType Directory -Force -Path (Join-Path $Dest 'agents') | Out-Null
  Get-ChildItem (Join-Path $ScriptDir 'agents') -Filter '*.md' -File | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $Dest "agents/$($_.Name)") -Force
    Write-Ok $_.Name
  }

  # ── 3. Skills ──────────────────────────────────────────────────────────────

  Write-Step '3/5' 'Skills'
  Get-ChildItem (Join-Path $ScriptDir 'skills') -Directory | ForEach-Object {
    $destSkill = Join-Path (Join-Path $Dest 'skills') $_.Name
    New-Item -ItemType Directory -Force -Path $destSkill | Out-Null
    Copy-Item "$($_.FullName)/*" $destSkill -Recurse -Force
    Write-Ok $_.Name
  }

  # ── 4. Commands ────────────────────────────────────────────────────────────

  Write-Step '4/5' 'Commands'
  New-Item -ItemType Directory -Force -Path (Join-Path $Dest 'commands') | Out-Null
  Get-ChildItem (Join-Path $ScriptDir 'commands') -Filter '*.md' -File | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $Dest "commands/$($_.Name)") -Force
    Write-Ok $_.Name
  }

  # ── 5. Cleanup legacy AGENTS.md ─────────────────────────────────────────────
  # TDD rules are now embedded in agent files (tdd.md, tdd-auto.md).
  # Remove old DevBlock section from global AGENTS.md if present (upgrade path).

  Write-Step '5/5' 'Cleanup legacy AGENTS.md'
  if (Test-AgentsMdHasDevBlock) {
    Remove-AgentsMdSection
  } else {
    Write-Ok 'No legacy DevBlock section to clean up'
  }

  # Post-install verification
  $okCount = 0; $missCount = 0
  foreach ($f in (Get-DevBlockFileList)) {
    if (Test-Path (Join-Path $Dest $f)) {
      $okCount++
    } else {
      Write-Warn "Missing after install: $f"
      $missCount++
    }
  }

  # ── Summary ────────────────────────────────────────────────────────────────

  Write-Host ''
  Write-Host "DevBlock v$DevBlockVersion installed successfully!" -ForegroundColor Green
  Write-Host ''
  Write-Host '  Plugin:   1'
  Write-Host '  Agents:   2 (TDD, TDD-Auto) — includes enforcement rules'
  Write-Host '  Skills:   5'
  Write-Host '  Commands: 1 (/tdd-status)'
  Write-Host "  Verified: $okCount/$($okCount + $missCount) files OK"
  Write-Host ''
  Write-Host 'How to use:'
  Write-Host '  1. Open any project with OpenCode'
  Write-Host '  2. Press Tab to switch to the TDD or TDD-Auto agent'
  Write-Host '  3. The plugin enforces RED/GREEN phases only when a TDD agent is active'
  Write-Host ''
  Write-Host 'Other commands:'
  Write-Host "  pwsh install.ps1 -Status      Show what is installed"
  Write-Host "  pwsh install.ps1 -Uninstall   Remove DevBlock completely"

  if ($missCount -gt 0) {
    Write-Host "`nWarning: $missCount file(s) missing after install — check the output above." -ForegroundColor Yellow
    exit 1
  }
}

# ─── Main ────────────────────────────────────────────────────────────────────

if ($Help) { Show-Help }
elseif ($Uninstall) { Start-Uninstall }
elseif ($Status) { Show-Status }
else { Start-Install }
