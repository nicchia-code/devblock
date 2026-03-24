# devblock-ctl.ps1 — Single writer of .scope.json (Cursor edition, PowerShell)
# Commands: init, status, next, back, scope-add, skip, stop
# Installed at: ~/.cursor/hooks/devblock/devblock-ctl.ps1

$ErrorActionPreference = "Stop"

$ProjectDir = if ($env:CURSOR_PROJECT_DIR) { $env:CURSOR_PROJECT_DIR } else { (Get-Location).Path }
$ScopeFile = Join-Path $ProjectDir ".scope.json"
$DevblockDir = Join-Path $ProjectDir ".devblock"
$Ctl = "powershell -ExecutionPolicy Bypass -File `"$(Join-Path $env:USERPROFILE '.cursor\hooks\devblock\devblock-ctl.ps1')`""

# ─── Helpers ─────────────────────────────────────────────────────────────────

function Die { param([string]$Msg) Write-Error "ERROR: $Msg"; exit 1 }
function Info { param([string]$Msg) Write-Output $Msg }
function Ok { param([string]$Msg) Write-Output $Msg }

function Require-Scope {
    if (-not (Test-Path $ScopeFile)) { Die "No active session. Start a TDD session first." }
}

function Require-Current {
    Require-Scope
    $scope = Get-Content $ScopeFile -Raw | ConvertFrom-Json
    if (-not $scope.current) { Die "No active feature. Start a TDD session first." }
}

function Get-Phase {
    $scope = Get-Content $ScopeFile -Raw | ConvertFrom-Json
    return $scope.current.phase
}

function Get-TestCommand {
    $scope = Get-Content $ScopeFile -Raw | ConvertFrom-Json
    $cmd = $scope.test_command
    if (-not $cmd) { $cmd = $scope.current.test_command }
    return $cmd
}

function Run-Tests {
    $testCmd = Get-TestCommand
    if (-not $testCmd) { Die "No test_command configured. Stop the session and start again with a test command." }
    Info "Running tests: $testCmd"
    Push-Location $ProjectDir
    try {
        $output = Invoke-Expression $testCmd 2>&1
        $output | Write-Output
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    } finally {
        Pop-Location
    }
}

function Auto-Commit {
    param([string]$FeatureName)
    $scope = Get-Content $ScopeFile -Raw | ConvertFrom-Json
    $files = @()
    if ($scope.current.files) { $files += $scope.current.files }
    if ($scope.current.tests) { $files += $scope.current.tests }
    if ($files.Count -eq 0) { Info "No files to commit."; return }

    $staged = 0
    foreach ($f in $files) {
        $fullPath = Join-Path $ProjectDir $f
        if (Test-Path $fullPath) {
            $diff = git -C $ProjectDir diff --name-only -- $f 2>$null
            $untracked = git -C $ProjectDir ls-files --others --exclude-standard -- $f 2>$null
            if ($diff -or $untracked) {
                git -C $ProjectDir add $f 2>$null
                $staged++
            }
        }
    }
    if ($staged -gt 0) {
        $result = git -C $ProjectDir commit -m "feat: $FeatureName" 2>$null
        if ($LASTEXITCODE -eq 0) { Ok "Auto-committed: $FeatureName" } else { Info "Nothing to commit." }
    } else {
        Info "No changes to commit."
    }
}

function Complete-Feature {
    $scope = Get-Content $ScopeFile -Raw | ConvertFrom-Json
    $featureName = $scope.current.name
    Auto-Commit $featureName

    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $scope = Get-Content $ScopeFile -Raw | ConvertFrom-Json

    # Move current to completed
    $completed = $scope.current | Select-Object *
    $completed | Add-Member -NotePropertyName "phase" -NotePropertyValue "done" -Force
    $completed | Add-Member -NotePropertyName "completed_at" -NotePropertyValue $now -Force
    if (-not $scope.completed) { $scope.completed = @() }
    $scope.completed += $completed
    $scope.current = $null

    $queueLen = if ($scope.queue) { $scope.queue.Count } else { 0 }
    if ($queueLen -gt 0) {
        $next = $scope.queue[0]
        $next | Add-Member -NotePropertyName "phase" -NotePropertyValue "red" -Force
        $next | Add-Member -NotePropertyName "started_at" -NotePropertyValue $now -Force
        $scope.current = $next
        $scope.queue = @($scope.queue | Select-Object -Skip 1)

        $scope | ConvertTo-Json -Depth 10 | Set-Content $ScopeFile -Encoding UTF8
        Ok "RED phase for: $($next.name)"
        Info "Write failing tests, then run: $Ctl next"
        Info "Remaining in queue: $($queueLen - 1)"
    } else {
        $scope | ConvertTo-Json -Depth 10 | Set-Content $ScopeFile -Encoding UTF8
        Ok "All features completed!"
    }
}

# ─── Commands ────────────────────────────────────────────────────────────────

function Cmd-Init {
    param([string]$Json)

    try { $parsed = $Json | ConvertFrom-Json } catch { Die "Invalid JSON. Fix the JSON syntax and try again." }

    $name = $parsed.current.name
    $phase = $parsed.current.phase
    $files = $parsed.current.files
    $tests = $parsed.current.tests
    $testCommand = $parsed.current.test_command

    if (-not $name) { Die "Missing current.name. Provide a feature name." }
    if (-not $phase) { Die "Missing current.phase. Set phase to 'red'." }
    if (-not $files) { Die "Missing current.files. Provide implementation file paths." }
    if (-not $tests) { Die "Missing current.tests. Provide test file paths." }
    if (-not $testCommand) { Die "Missing current.test_command. Provide a test command." }

    # Create .devblock directory
    if (-not (Test-Path $DevblockDir)) { New-Item -ItemType Directory -Path $DevblockDir -Force | Out-Null }

    # Update .gitignore
    $gitignore = Join-Path $ProjectDir ".gitignore"
    if (Test-Path $gitignore) {
        $content = Get-Content $gitignore -Raw
        if ($content -notmatch '\.scope\.json') { Add-Content $gitignore ".scope.json" }
        if ($content -notmatch '\.devblock') { Add-Content $gitignore ".devblock/" }
    } else {
        ".scope.json`n.devblock/`n" | Set-Content $gitignore -Encoding UTF8
    }

    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Build enriched scope
    $scope = @{
        session = $now
        test_command = $testCommand
        current = @{
            name = $name
            phase = $phase
            files = @($files)
            tests = @($tests)
            started_at = $now
        }
        queue = if ($parsed.queue) { @($parsed.queue) } else { @() }
        completed = @()
    }

    $scope | ConvertTo-Json -Depth 10 | Set-Content $ScopeFile -Encoding UTF8
    Ok "Session started: $name (RED phase)"
    Info "Write failing tests, then run: $Ctl next"
}

function Cmd-Status {
    if (-not (Test-Path $ScopeFile)) { Info "No active session."; return }
    Get-Content $ScopeFile -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 10 | Write-Output
}

function Cmd-Next {
    Require-Current
    $phase = Get-Phase

    switch ($phase) {
        "red" {
            Info "Validating: tests must FAIL in RED phase..."
            if (Run-Tests) {
                Info "Tests already passing -- fast-forwarding through GREEN."
                Complete-Feature
                return
            }
            Ok "Tests correctly failing. Moving to GREEN phase."
            $scope = Get-Content $ScopeFile -Raw | ConvertFrom-Json
            $scope.current.phase = "green"
            $scope | ConvertTo-Json -Depth 10 | Set-Content $ScopeFile -Encoding UTF8
            Info "GREEN phase. Make tests pass, then run: $Ctl next"
        }
        "green" {
            Info "Validating: tests must PASS in GREEN phase..."
            if (-not (Run-Tests)) {
                Die "Tests still FAILING. Fix implementation, then run: $Ctl next"
            }
            Ok "Tests passing. Feature complete!"
            Complete-Feature
        }
        default {
            Die "Unexpected phase '$phase'. Run: $Ctl status"
        }
    }
}

function Cmd-Back {
    Require-Current
    $phase = Get-Phase
    if ($phase -ne "green") { Die "Already in $phase phase. 'back' only works from GREEN." }

    $scope = Get-Content $ScopeFile -Raw | ConvertFrom-Json
    $scope.current.phase = "red"
    $scope | ConvertTo-Json -Depth 10 | Set-Content $ScopeFile -Encoding UTF8
    Ok "Back to RED phase. Fix your tests, then run: $Ctl next"
}

function Cmd-ScopeAdd {
    param([string]$File, [switch]$Test)
    Require-Current

    if (-not $File) { Die "Provide a file path. Usage: $Ctl scope-add <file> [--test]" }
    if ($File -eq ".scope.json" -or $File -like "*/.scope.json") { Die "Do not add .scope.json to scope." }

    $scope = Get-Content $ScopeFile -Raw | ConvertFrom-Json
    $targetArray = if ($Test) { "tests" } else { "files" }

    $existing = @($scope.current.$targetArray | Where-Object { $_ -eq $File })
    if ($existing.Count -gt 0) { Die "$File is already in scope ($targetArray)." }

    $scope.current.$targetArray += $File
    $scope | ConvertTo-Json -Depth 10 | Set-Content $ScopeFile -Encoding UTF8
    Ok "Added $File to $targetArray scope."
}

function Cmd-Skip {
    param([string]$Reason)
    if (-not $Reason) { Die "Usage: $Ctl skip --reason `"...`"" }
    if (-not (Test-Path $ScopeFile)) { Die "No active session." }

    if (-not (Test-Path $DevblockDir)) { New-Item -ItemType Directory -Path $DevblockDir -Force | Out-Null }

    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $token = @{ reason = $Reason; created_at = $now } | ConvertTo-Json
    $token | Set-Content (Join-Path $DevblockDir ".skip-token") -Encoding UTF8

    $scope = Get-Content $ScopeFile -Raw | ConvertFrom-Json
    $phase = if ($scope.current) { $scope.current.phase } else { "none" }
    $feature = if ($scope.current) { $scope.current.name } else { "none" }
    "$now | phase=$phase | feature=$feature | reason: $Reason" | Add-Content (Join-Path $DevblockDir "skips.log")

    Write-Output "Skip token created. You may now make ONE edit outside the current phase."
    Write-Output "Reason logged: $Reason"
}

function Cmd-Stop {
    param([switch]$Full)
    if (-not (Test-Path $ScopeFile)) {
        Write-Output '{"ok":false,"error":"No active session."}'
        exit 1
    }

    $scope = Get-Content $ScopeFile -Raw | ConvertFrom-Json
    $currentName = if ($scope.current) { $scope.current.name } else { "none" }
    $phase = if ($scope.current) { $scope.current.phase } else { "none" }
    $queueLen = if ($scope.queue) { $scope.queue.Count } else { 0 }

    Remove-Item $ScopeFile -Force
    $msg = "Session closed. Feature: $currentName (phase: $phase), queue: $queueLen remaining."

    if ($Full) {
        if (Test-Path $DevblockDir) { Remove-Item $DevblockDir -Recurse -Force }
        $msg += " Cleaned up .devblock/ directory."
    }

    Write-Output "{`"ok`":true,`"message`":`"$msg`"}"
}

# ─── Main ────────────────────────────────────────────────────────────────────

$cmd = $args[0]
$remaining = $args[1..($args.Count - 1)]

switch ($cmd) {
    "init"      { Cmd-Init ($remaining -join " ") }
    "status"    { Cmd-Status }
    "next"      { Cmd-Next }
    "back"      { Cmd-Back }
    "scope-add" {
        $file = $remaining[0]
        $isTest = $remaining -contains "--test"
        Cmd-ScopeAdd -File $file -Test:$isTest
    }
    "skip" {
        $reason = ""
        for ($i = 0; $i -lt $remaining.Count; $i++) {
            if ($remaining[$i] -eq "--reason" -and ($i + 1) -lt $remaining.Count) {
                $reason = $remaining[$i + 1]
            }
        }
        Cmd-Skip -Reason $reason
    }
    "stop" {
        $full = $remaining -contains "--full"
        Cmd-Stop -Full:$full
    }
    default { Die "Unknown command '$cmd'. Use one of: init, status, next, back, scope-add, skip, stop." }
}
