# session-stop.ps1 — stop hook for DevBlock (Cursor)
# Warns user if TDD session is still active when closing.
# Installed at: ~/.cursor/hooks/devblock/session-stop.ps1

$ErrorActionPreference = "SilentlyContinue"

$ProjectDir = if ($env:CURSOR_PROJECT_DIR) { $env:CURSOR_PROJECT_DIR } else { "." }
$ScopeFile = Join-Path $ProjectDir ".scope.json"

if (Test-Path $ScopeFile) {
    try {
        $scope = Get-Content $ScopeFile -Raw | ConvertFrom-Json
        $name = $scope.current.name
        $phase = $scope.current.phase

        if ($name -and $phase) {
            Write-Output "{`"user_message`":`"DevBlock: TDD session still active (feature: '$name', phase: $phase). It will resume automatically in your next session.`"}"
        }
    } catch {}
}

exit 0
