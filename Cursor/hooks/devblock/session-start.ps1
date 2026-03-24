# session-start.ps1 — sessionStart hook for DevBlock (Cursor)
# Injects TDD rules and active session state into agent context.
# Installed at: ~/.cursor/hooks/devblock/session-start.ps1

$ErrorActionPreference = "SilentlyContinue"

$ProjectDir = if ($env:CURSOR_PROJECT_DIR) { $env:CURSOR_PROJECT_DIR } else { "." }
$ScopeFile = Join-Path $ProjectDir ".scope.json"
$Ctl = "powershell -ExecutionPolicy Bypass -File `"$(Join-Path $env:USERPROFILE '.cursor\hooks\devblock\devblock-ctl.ps1')`""

# Always inject the base rules
$Rules = "DevBlock TDD Enforcement is active."
$Rules += " Rules: (1) RED phase: only test files writable. (2) GREEN phase: only impl files writable."
$Rules += " (3) Files must be in scope. (4) Never edit .scope.json directly."
$Rules += " (5) File-modifying shell is blocked; use Write tool. (6) Skip requires reason + user confirmation, single-use."
$Rules += " (7) Never skip without genuine need."
$Rules += " Commands: init=$Ctl init '<JSON>', status=$Ctl status, next=$Ctl next,"
$Rules += " back=$Ctl back, scope-add=$Ctl scope-add <file> [--test],"
$Rules += " skip=$Ctl skip --reason '...', stop=$Ctl stop [--full]."
$Rules += " Workflow: ask user for feature name+files+tests+test_command, build JSON, run init, write failing tests (RED),"
$Rules += " run next (validates tests fail, moves to GREEN), implement (GREEN), run next (validates tests pass, auto-commits)."
$Rules += " Stop is user-only. Never stop autonomously."

# If active session, append current state
if (Test-Path $ScopeFile) {
    try {
        $scope = Get-Content $ScopeFile -Raw | ConvertFrom-Json
        $name = $scope.current.name
        $phase = $scope.current.phase

        if ($name -and $phase) {
            $files = ($scope.current.files | Where-Object { $_ }) -join ", "
            $tests = ($scope.current.tests | Where-Object { $_ }) -join ", "
            $queueLen = if ($scope.queue) { $scope.queue.Count } else { 0 }
            $Rules += " ACTIVE SESSION: feature='$name', phase=$phase, impl=[$files], tests=[$tests], queue=$queueLen."
        }
    } catch {}
}

$Rules = $Rules -replace '"', '\"'
Write-Output "{`"agent_message`":`"$Rules`"}"
exit 0
