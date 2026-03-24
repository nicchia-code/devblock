# scope-guard.ps1 — preToolUse / beforeShellExecution hook for DevBlock (Cursor)
# Enforces scope locking and RED/GREEN phase constraints.
# Installed at: ~/.cursor/hooks/devblock/scope-guard.ps1

$ErrorActionPreference = "SilentlyContinue"

$ProjectDir = if ($env:CURSOR_PROJECT_DIR) { $env:CURSOR_PROJECT_DIR } else { "." }
$ScopeFile = Join-Path $ProjectDir ".scope.json"
$DevblockDir = Join-Path $ProjectDir ".devblock"
$Ctl = Join-Path $env:USERPROFILE ".cursor\hooks\devblock\devblock-ctl.ps1"
$CtlCmd = "powershell -ExecutionPolicy Bypass -File `"$Ctl`""

# ─── Helpers ─────────────────────────────────────────────────────────────────

function Allow {
    Write-Output '{"permission":"allowed"}'
    exit 0
}

function Deny {
    param([string]$UserMsg, [string]$AgentMsg = "")
    if (-not $AgentMsg) { $AgentMsg = $UserMsg }
    $UserMsg = $UserMsg -replace '"', '\"'
    $AgentMsg = $AgentMsg -replace '"', '\"'
    Write-Output "{`"permission`":`"denied`",`"user_message`":`"$UserMsg`",`"agent_message`":`"DEVBLOCK DENIED: $AgentMsg`"}"
    exit 2
}

# ─── Detect hook type ────────────────────────────────────────────────────────

$IsShell = $args -contains "--shell"

# ─── Read hook input ─────────────────────────────────────────────────────────

$RawInput = $input | Out-String
if (-not $RawInput) { Allow }

try {
    $HookInput = $RawInput | ConvertFrom-Json
} catch {
    Allow
}

# ─── No session → allow everything ───────────────────────────────────────────

if (-not (Test-Path $ScopeFile)) { Allow }

try {
    $Scope = Get-Content $ScopeFile -Raw | ConvertFrom-Json
} catch {
    Allow
}

$Current = $Scope.current
$Phase = if ($Current) { $Current.phase } else { $null }

# ─── File Edit Tools (preToolUse) ────────────────────────────────────────────

if (-not $IsShell) {
    $ToolName = $HookInput.tool_name

    # Only intercept Write tool
    if ($ToolName -ne "Write") { Allow }

    # Extract file path
    $FilePath = $HookInput.tool_input.file_path
    if (-not $FilePath) { $FilePath = $HookInput.tool_input.target_file }
    if (-not $FilePath) { $FilePath = $HookInput.tool_input.path }
    if (-not $FilePath) { Allow }

    # Normalize path — strip project dir prefix
    $FilePath = $FilePath -replace [regex]::Escape("$ProjectDir/"), ""
    $FilePath = $FilePath -replace [regex]::Escape("$ProjectDir\"), ""
    $FilePath = $FilePath -replace "^\./", ""
    $FilePath = $FilePath -replace "^\.\\", ""
    # Normalize backslashes to forward slashes for comparison
    $FilePath = $FilePath -replace "\\", "/"

    # Block .scope.json edits
    if ($FilePath -eq ".scope.json" -or $FilePath -like "*/.scope.json") {
        Deny "BLOCKED: Do not edit .scope.json directly." `
             "Do not edit .scope.json. To advance phase: $CtlCmd next. To add files: $CtlCmd scope-add <file>."
    }

    # Files outside project are not our concern
    if ($FilePath -match "^[A-Za-z]:" -or $FilePath.StartsWith("/")) { Allow }

    # No active feature
    if (-not $Current) {
        Deny "BLOCKED: No active feature." `
             "No active feature. Start a TDD session first by asking the user for feature details and running: $CtlCmd init '<JSON>'"
    }

    # Check scope membership
    $ImplFiles = @($Current.files | Where-Object { $_ })
    $TestFiles = @($Current.tests | Where-Object { $_ })
    $InFiles = ($ImplFiles -contains $FilePath)
    $InTests = ($TestFiles -contains $FilePath)

    # File not in scope
    if (-not $InFiles -and -not $InTests) {
        $ScopeList = ($ImplFiles + $TestFiles) -join ", "
        Deny "BLOCKED: '$FilePath' not in scope. Scoped files: $ScopeList" `
             "'$FilePath' not in scope. Add it first: $CtlCmd scope-add $FilePath [--test]"
    }

    # Skip token: single-use phase bypass
    $SkipToken = Join-Path $DevblockDir ".skip-token"
    if (Test-Path $SkipToken) {
        Remove-Item $SkipToken -Force
        Allow
    }

    # RED phase: only test files editable
    if ($InFiles -and -not $InTests -and $Phase -eq "red") {
        Deny "BLOCKED: RED phase -- only test files editable. Write failing tests first." `
             "RED phase -- only test files editable. Write failing tests, then run: $CtlCmd next. To bypass once: $CtlCmd skip --reason `"...`""
    }

    # GREEN phase: only impl files editable
    if ($InTests -and $Phase -eq "green") {
        Deny "BLOCKED: GREEN phase -- only impl files editable. Make tests pass." `
             "GREEN phase -- only impl files editable. Make tests pass, then run: $CtlCmd next. If tests are wrong: $CtlCmd back. To bypass once: $CtlCmd skip --reason `"...`""
    }

    Allow
}

# ─── Shell Commands (beforeShellExecution) ───────────────────────────────────

if ($IsShell) {
    $Command = $HookInput.command
    if (-not $Command) { Allow }

    # Whitelist devblock-ctl calls
    if ($Command -match "devblock-ctl\.(sh|ps1)") { Allow }

    # No active feature → allow all shell
    if (-not $Current) { Allow }

    # Whitelist readonly commands
    if ($Command -match "^\s*(ls|cat|echo|find|which|file|stat|du|df|wc|head|tail|pwd|date|env|dir|type|Get-Content|Get-ChildItem)\s") { Allow }

    # Block file-modifying patterns
    $ModPatterns = "([^2]>\s*[^&/]|[^0-9]>>\s*[^/]|sed\s+-i|tee\s+|rm\s+|mv\s+|cp\s+|Remove-Item|Move-Item|Copy-Item|Set-Content|Out-File)"
    if ($Command -match $ModPatterns) {
        # Whitelist test runners and git
        $TestPatterns = "^\s*(git\s+|npm\s+test|npx\s+|yarn\s+test|pnpm\s+test|pytest|python\s+-m\s+pytest|cargo\s+test|go\s+test|make\s+test|bundle\s+exec\s+rspec|jest|vitest|mocha|bun\s+test|dotnet\s+test)"
        if ($Command -match $TestPatterns) { Allow }

        Deny "BLOCKED: Do not modify files via shell. Use the Write tool instead -- it is scope-checked." `
             "Do not modify files via shell. Use the Write tool instead -- it is scope-checked by DevBlock."
    }

    Allow
}

# ─── Default: allow unknown hook types ───────────────────────────────────────

Allow
