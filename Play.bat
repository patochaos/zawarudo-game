@echo off
REM ---------------------------------------------------------------------------
REM  Tactical Duel Prototype - play the exported build.
REM  This is the one to hand a playtester: it needs nothing installed.
REM ---------------------------------------------------------------------------
setlocal
cd /d "%~dp0"

set "EXE=build\windows\TacticalDuel.exe"
REM A running Windows build cannot be overwritten. When an export had to use
REM the fallback name, launch whichever build is newest instead of a stale EXE.
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "$c = Get-Item -ErrorAction SilentlyContinue 'build\windows\TacticalDuel.exe','build\windows\ZAWARUDO-latest.exe'; $c | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName"`) do set "EXE=%%i"

if exist "%EXE%" (
    start "" "%EXE%"
    exit /b 0
)

echo.
echo   Build not found:  %EXE%
echo.
echo   Export it from the Godot editor ^(Project ^> Export ^> Windows^),
echo   or run Build.bat, or use Play-Source.bat to run the code directly.
echo.
pause
exit /b 1
