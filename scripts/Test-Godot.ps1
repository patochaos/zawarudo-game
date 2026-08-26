[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

$godotCommand = Get-Command godot -ErrorAction SilentlyContinue
if ($godotCommand) {
    $godot = $godotCommand.Source
} elseif (Test-Path -LiteralPath "D:\Godot\godot.cmd") {
    $godot = "D:\Godot\godot.cmd"
} else {
    throw "Godot is not on PATH or at D:\Godot\godot.cmd."
}

# Branch switches can leave Godot's ignored global class cache stale. Refresh it
# before invoking scripts directly so a new class_name never passes only because
# another worktree happened to scan it first.
& $godot --headless --editor --path $projectRoot --quit
if ($LASTEXITCODE -ne 0) {
    throw "Godot could not refresh the project class cache (exit $LASTEXITCODE)."
}

$tests = Get-ChildItem -LiteralPath (Join-Path $projectRoot "tests") -Filter "*.gd" |
    Where-Object {
        $_.BaseName -notin @("CharacterBalanceSimulation", "VisualCaptureHelper") -and
        -not (Select-String -LiteralPath $_.FullName -SimpleMatch "VisualCaptureHelper" -Quiet)
    } |
    Sort-Object Name |
    Select-Object -ExpandProperty BaseName

if ($tests.Count -eq 0) {
    throw "No Godot test suites were found."
}

$failed = [System.Collections.Generic.List[string]]::new()
foreach ($test in $tests) {
    Write-Host "RUN $test"
    & $godot --headless --path $projectRoot --script "res://tests/$test.gd"
    if ($LASTEXITCODE -ne 0) {
        $failed.Add($test)
    }
}

if ($failed.Count -gt 0) {
    throw "Godot test failures: $($failed -join ', ')"
}

Write-Host "All $($tests.Count) Godot gameplay and journey suites passed."
