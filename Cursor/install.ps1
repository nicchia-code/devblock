# install.ps1 — Install DevBlock for Cursor (Windows)
# Installs skills + hooks globally to ~/.cursor/

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$Dest = Join-Path $env:USERPROFILE ".cursor"
$SkillsDir = Join-Path $Dest "skills"
$HooksScripts = Join-Path $Dest "hooks\devblock"

function Die { param([string]$Msg) Write-Error "ERROR: $Msg"; exit 1 }
function Ok { param([string]$Msg) Write-Host "  OK: $Msg" }

# Validate source — we read from the repo root (Claude Code plugin format)
if (-not (Test-Path (Join-Path $RepoRoot "CLAUDE.md"))) { Die "Cannot find CLAUDE.md in $RepoRoot. Run from Cursor\ directory." }
if (-not (Test-Path (Join-Path $RepoRoot "skills"))) { Die "Cannot find skills\ in $RepoRoot." }
if (-not (Test-Path (Join-Path $RepoRoot "hooks"))) { Die "Cannot find hooks\ in $RepoRoot." }

Write-Host "Installing DevBlock to: $Dest"
Write-Host ""

# ─── 1. Skills ───────────────────────────────────────────────────────────────

Write-Host "Installing skills..."
Get-ChildItem (Join-Path $RepoRoot "skills") -Directory | ForEach-Object {
    $skillName = $_.Name
    $destSkill = Join-Path $SkillsDir "devblock-$skillName"
    New-Item -ItemType Directory -Force -Path $destSkill | Out-Null
    Copy-Item (Join-Path $_.FullName "SKILL.md") (Join-Path $destSkill "SKILL.md") -Force
    Ok "devblock-$skillName"
}

# ─── 2. Hook scripts (Cursor-adapted PowerShell versions) ───────────────────

Write-Host ""
Write-Host "Installing hook scripts..."
New-Item -ItemType Directory -Force -Path $HooksScripts | Out-Null
Copy-Item (Join-Path $ScriptDir "hooks\devblock\scope-guard.ps1") (Join-Path $HooksScripts "scope-guard.ps1") -Force
Copy-Item (Join-Path $ScriptDir "hooks\devblock\devblock-ctl.ps1") (Join-Path $HooksScripts "devblock-ctl.ps1") -Force
Ok "scope-guard.ps1 (Cursor format)"
Ok "devblock-ctl.ps1 (Cursor paths)"

# ─── 3. Register hooks in hooks.json (Cursor format) ────────────────────────

Write-Host ""
Write-Host "Registering hooks..."

$HooksJson = Join-Path $Dest "hooks.json"
$PsPrefix = "powershell -ExecutionPolicy Bypass -File"
$GuardPath = Join-Path $HooksScripts "scope-guard.ps1"

$HooksConfig = @{
    version = 1
    hooks = @{
        preToolUse = @(@{
            command = "$PsPrefix `"$GuardPath`""
            type = "command"
            matcher = "Write"
            timeout = 10
            failClosed = $false
        })
        beforeShellExecution = @(@{
            command = "$PsPrefix `"$GuardPath`" --shell"
            type = "command"
            timeout = 10
            failClosed = $false
        })
    }
}

if (Test-Path $HooksJson) {
    # Merge: remove old devblock hooks, add new ones
    $existing = Get-Content $HooksJson -Raw | ConvertFrom-Json

    $hookTypes = @("preToolUse", "beforeShellExecution")
    foreach ($hookType in $hookTypes) {
        if ($existing.hooks.$hookType) {
            $existing.hooks.$hookType = @($existing.hooks.$hookType | Where-Object {
                $_.command -notmatch "devblock"
            })
            $existing.hooks.$hookType += $HooksConfig.hooks.$hookType
        } else {
            $existing.hooks | Add-Member -NotePropertyName $hookType -NotePropertyValue $HooksConfig.hooks.$hookType -Force
        }
    }

    $existing | ConvertTo-Json -Depth 10 | Set-Content $HooksJson -Encoding UTF8
    Ok "Merged hooks into existing $HooksJson"
} else {
    $HooksConfig | ConvertTo-Json -Depth 10 | Set-Content $HooksJson -Encoding UTF8
    Ok "Created $HooksJson"
}

# ─── 4. Write Cursor-adapted start skill (replaces Claude Code version) ──────

Write-Host ""
Write-Host "Writing Cursor-adapted skills..."

$CtlPath = Join-Path $HooksScripts "devblock-ctl.ps1"
$CtlCmd = "$PsPrefix `"$CtlPath`""

$StartSkill = @"
---
name: start
description: Start a DevBlock TDD session
user_invocable: true
---

# /devblock-start — Start TDD session

## Steps

1. DevBlock is installed globally. The controller is at ``$CtlPath``.

2. **Check for an existing plan first.** Look in ``.cursor/plans/`` and ``~/.cursor/plans/`` for recent ``.plan.md`` files related to the current project. If a plan exists, extract feature name, files, tests, and queue from it — propose these to the user for confirmation instead of asking from scratch.

3. If no plan exists (or the plan doesn't cover TDD details), ask the user for:
   - **Feature name** (short description)
   - **Implementation files** (paths or globs — resolve with Glob)
   - **Test files** (propose based on project conventions)
   - **Test command** (detect from package.json, Makefile, etc.)
   - **Queue** (optional: additional features as ``name | files | tests``)

4. Build JSON and call:
   ``````bash
   $CtlCmd init '<JSON>'
   ``````

   JSON format:
   ``````json
   {
     "current": {
       "name": "Feature name",
       "phase": "red",
       "files": ["src/module.ts"],
       "tests": ["tests/module.test.ts"],
       "test_command": "npm test -- tests/module.test.ts"
     },
     "queue": []
   }
   ``````

5. Confirm session started. Begin writing failing tests immediately.

> **Note:** If you need to edit outside the current phase, use ``/devblock-skip`` — it requires a reason and user approval.
"@

Set-Content (Join-Path $SkillsDir "devblock-start\SKILL.md") $StartSkill -Encoding UTF8
Ok "devblock-start (Cursor-adapted with plan detection)"

# Patch remaining skills: replace .devblock/ paths with global paths
Get-ChildItem (Join-Path $SkillsDir "devblock-*") -Filter "SKILL.md" -Recurse | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $content = $content -replace "bash \.devblock/devblock-ctl\.sh", $CtlCmd
    $content = $content -replace "/devblock:skip", "/devblock-skip"
    $content = $content -replace "/devblock:next", "/devblock-next"
    $content = $content -replace "/devblock:start", "/devblock-start"
    $content = $content -replace "/devblock:stop", "/devblock-stop"
    $content = $content -replace "/devblock:add", "/devblock-add"
    Set-Content $_.FullName $content -Encoding UTF8
}
Ok "All skills patched with global paths and Cursor skill names"

# ─── Done ────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "DevBlock installed successfully!"
Write-Host ""
Write-Host "Skills installed:"
Get-ChildItem $SkillsDir -Directory | Where-Object { $_.Name -like "devblock-*" } | ForEach-Object { Write-Host "  $($_.Name)" }
Write-Host ""
Write-Host "How to use:"
Write-Host "  1. Open any project in Cursor"
Write-Host "  2. Type /devblock-start to begin a TDD session"
Write-Host "  3. Hooks enforce RED/GREEN phase automatically"
Write-Host ""
Write-Host "To uninstall:"
Write-Host "  Remove-Item -Recurse $HooksScripts"
Write-Host "  Remove-Item -Recurse $SkillsDir\devblock-*"
Write-Host "  Edit $HooksJson to remove devblock entries"
