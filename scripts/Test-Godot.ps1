[CmdletBinding()]
param(
    [string[]]$Suite = @(),
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 300
)

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

# Capture both streams: Godot can log errors and still exit successfully.
function Invoke-GodotCheck([string[]]$GodotArguments) {
    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath $godot -ArgumentList $GodotArguments `
            -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            # Include the child executable when godot is a .cmd launcher.
            & taskkill.exe /PID $process.Id /T /F | Out-Null
            $process.WaitForExit()
        }
        $process.Refresh()
        $output = (Get-Content -LiteralPath $stdout, $stderr -Raw) -join "`n"
        Write-Host $output
        if ($timedOut) {
            Write-Host "Godot timed out after $TimeoutSeconds seconds."
        }
        return (-not $timedOut -and $process.ExitCode -eq 0 -and $output -notmatch 'ERROR:')
    } finally {
        Remove-Item -LiteralPath $stdout, $stderr -Force
    }
}

# Refresh imported resources and the global class cache before standalone suites.
if (-not (Invoke-GodotCheck @('--headless', '--editor', '--path', "`"$projectRoot`"", '--quit'))) {
    throw "Godot could not import the project cleanly."
}

$tests = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot "tests") -Filter "*.gd" |
    Where-Object {
        $_.BaseName -notin @("CharacterBalanceSimulation", "VisualCaptureHelper") -and
        -not (Select-String -LiteralPath $_.FullName -SimpleMatch "VisualCaptureHelper" -Quiet)
    } |
    Sort-Object Name |
    Select-Object -ExpandProperty BaseName)

foreach ($name in $Suite) {
    if ($name -notin $tests) { throw "Unknown runnable suite: $name" }
}
if ($Suite.Count -gt 0) { $tests = @($tests | Where-Object { $_ -in $Suite }) }
if ($tests.Count -eq 0) { throw "No Godot test suites were found." }

$failed = [System.Collections.Generic.List[string]]::new()
foreach ($test in $tests) {
    Write-Host "RUN $test"
    $godotArguments = @('--headless')
    if ($test -eq 'FighterFashionPolygonTest') {
        $godotArguments = @('--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--disable-vsync')
    }
    $godotArguments += @('--path', "`"$projectRoot`"", '--script', "res://tests/$test.gd")
    if (-not (Invoke-GodotCheck $godotArguments)) { $failed.Add($test) }
}

if ($failed.Count -gt 0) { throw "Godot test failures: $($failed -join ', ')" }
Write-Host "All $($tests.Count) Godot suites passed."
