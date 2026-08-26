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

$tests = @(
    "FighterVisualTest",
    "KnifeMechanicsTest",
    "OnlineLockstepTest",
    "DoubleJumpTest",
    "PlaytestReadinessTest",
    "FourPlayerModeTest",
    "SuperCutInTest",
    "KineticArenaTest",
    "TouchControlsTest",
	"KenneyPolishTest",
	"MenuInteractionTest",
	"GrenadierTest",
	"DashbladeTest",
	"ChakramTest",
	"ShockWeaponTest",
	"CharacterKitsTest",
	"CharacterSelectTest",
	"TeamBattleTest",
	"MatchReplayTest",
    "CloseCameraTest",
    "LevelLayoutTest",
    "UserJourneyTest"
)

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

Write-Host "All established Godot gameplay and journey suites passed."
