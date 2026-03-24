# install.ps1 — Install DevBlock for Cursor (Windows)
# Installs hooks to ~/.cursor/ (user-level, applies to all projects)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dest = Join-Path $env:USERPROFILE ".cursor"
$HooksDir = Join-Path $Dest "hooks\devblock"

function Die { param([string]$Msg) Write-Error "ERROR: $Msg"; exit 1 }
function Ok { param([string]$Msg) Write-Host $Msg }

# Validate source files
$SourceDir = Join-Path $ScriptDir "hooks\devblock"
if (-not (Test-Path $SourceDir)) { Die "Cannot find hooks\devblock\ in $ScriptDir" }

Write-Host "Installing DevBlock to: $Dest"

# Create hooks directory
New-Item -ItemType Directory -Force -Path $HooksDir | Out-Null

# Copy PowerShell scripts
$scripts = @("scope-guard.ps1", "devblock-ctl.ps1", "session-start.ps1", "pre-compact.ps1", "session-stop.ps1")
foreach ($script in $scripts) {
    $src = Join-Path $SourceDir $script
    if (-not (Test-Path $src)) { Die "Missing: hooks\devblock\$script" }
    Copy-Item $src (Join-Path $HooksDir $script) -Force
}

# Generate hooks.json entries for Windows
$PsPrefix = "powershell -ExecutionPolicy Bypass -File"
$DevblockHooks = @{
    preToolUse = @(@{
        command = "$PsPrefix `"$HooksDir\scope-guard.ps1`""
        type = "command"
        matcher = "Write"
        timeout = 10
        failClosed = $false
    })
    beforeShellExecution = @(@{
        command = "$PsPrefix `"$HooksDir\scope-guard.ps1`" --shell"
        type = "command"
        timeout = 10
        failClosed = $false
    })
    sessionStart = @(@{
        command = "$PsPrefix `"$HooksDir\session-start.ps1`""
        type = "command"
        timeout = 5
    })
    preCompact = @(@{
        command = "$PsPrefix `"$HooksDir\pre-compact.ps1`""
        type = "command"
        timeout = 5
    })
    stop = @(@{
        command = "$PsPrefix `"$HooksDir\session-stop.ps1`""
        type = "command"
        timeout = 5
    })
}

$HooksJson = Join-Path $Dest "hooks.json"

if (Test-Path $HooksJson) {
    # Merge with existing hooks.json
    $existing = Get-Content $HooksJson -Raw | ConvertFrom-Json

    # Remove any existing devblock entries
    $hookTypes = @("preToolUse", "beforeShellExecution", "sessionStart", "preCompact", "stop")
    foreach ($hookType in $hookTypes) {
        if ($existing.hooks.$hookType) {
            $existing.hooks.$hookType = @($existing.hooks.$hookType | Where-Object {
                $_.command -notmatch "devblock"
            })
        } else {
            $existing.hooks | Add-Member -NotePropertyName $hookType -NotePropertyValue @() -Force
        }
        # Add devblock hooks
        $existing.hooks.$hookType += $DevblockHooks.$hookType
    }

    $existing | ConvertTo-Json -Depth 10 | Set-Content $HooksJson -Encoding UTF8
    Ok "Merged DevBlock hooks into existing $HooksJson"
} else {
    # Create new hooks.json
    $config = @{
        version = 1
        hooks = $DevblockHooks
    }
    $config | ConvertTo-Json -Depth 10 | Set-Content $HooksJson -Encoding UTF8
    Ok "Created $HooksJson"
}

Ok ""
Ok "DevBlock installed successfully!"
Ok ""
Ok "How it works:"
Ok "  - Hooks are active on ALL projects you open in Cursor"
Ok "  - Ask the Cursor agent to start a TDD session"
Ok "  - The sessionStart hook injects rules automatically"
Ok "  - .scope.json and .devblock/ are created per-project (add to .gitignore)"
Ok ""
Ok "To uninstall: Remove-Item -Recurse $HooksDir; then edit $HooksJson to remove devblock entries"
