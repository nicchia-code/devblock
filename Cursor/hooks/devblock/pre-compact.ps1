# pre-compact.ps1 — preCompact hook for DevBlock (Cursor)
# Preserves TDD state across context compaction.
# Installed at: ~/.cursor/hooks/devblock/pre-compact.ps1

$ErrorActionPreference = "SilentlyContinue"

$ProjectDir = if ($env:CURSOR_PROJECT_DIR) { $env:CURSOR_PROJECT_DIR } else { "." }
$ScopeFile = Join-Path $ProjectDir ".scope.json"
$Ctl = "powershell -ExecutionPolicy Bypass -File `"$(Join-Path $env:USERPROFILE '.cursor\hooks\devblock\devblock-ctl.ps1')`""

if (Test-Path $ScopeFile) {
    try {
        $scope = Get-Content $ScopeFile -Raw | ConvertFrom-Json
        if ($scope.current) {
            $state = @{
                feature = $scope.current.name
                phase = $scope.current.phase
                files = $scope.current.files
                tests = $scope.current.tests
                queue_len = if ($scope.queue) { $scope.queue.Count } else { 0 }
                completed_len = if ($scope.completed) { $scope.completed.Count } else { 0 }
            } | ConvertTo-Json -Compress

            $state = $state -replace '"', '\"'
            $msg = "DEVBLOCK STATE (preserve across compaction): $state. Commands: next=$Ctl next, back=$Ctl back, scope-add=$Ctl scope-add <file>, skip=$Ctl skip --reason '...', stop=$Ctl stop."
            Write-Output "{`"agent_message`":`"$msg`"}"
        }
    } catch {}
}

exit 0
