@echo off
REM ---------------------------------------------------------------------------
REM  Tactical Duel Prototype - run the current source with Godot.
REM  Use this while iterating: it picks up code edits with no re-export.
REM
REM  If Godot lives somewhere else, change this one line:
REM ---------------------------------------------------------------------------
set "GODOT_DIR=D:\Godot"

setlocal
cd /d "%~dp0"

REM Prefer the windowed executable so no console window hangs around. The
REM `_console` build is skipped: the glob cannot match it, since that name ends
REM in _console.exe rather than _win64.exe.
set "GODOT="
for /f "delims=" %%i in ('dir /b /a-d "%GODOT_DIR%\Godot_v*_win64.exe" 2^>nul') do (
    if not defined GODOT set "GODOT=%GODOT_DIR%\%%i"
)

REM Fall back to whatever `godot` resolves to on PATH (often a .cmd shim, which
REM start^(^) cannot resolve by bare name -- hence resolving it to a full path).
if not defined GODOT for /f "delims=" %%i in ('where godot 2^>nul') do (
    if not defined GODOT set "GODOT=%%i"
)

if not defined GODOT goto :nogodot

start "" "%GODOT%" --path "%CD%" %*
exit /b 0

:nogodot
echo.
echo   Godot was not found.
echo   Looked in "%GODOT_DIR%" and on PATH.
echo   Edit GODOT_DIR at the top of this file to point at your install.
echo.
pause
exit /b 1
