@echo off
REM ---------------------------------------------------------------------------
REM  Tactical Duel Prototype - play the exported build.
REM  This is the one to hand a playtester: it needs nothing installed.
REM ---------------------------------------------------------------------------
setlocal
cd /d "%~dp0"

set "EXE=build\windows\TacticalDuel.exe"

if exist "%EXE%" (
    start "" "%EXE%"
    exit /b 0
)

echo.
echo   Build not found:  %CD%\%EXE%
echo.
echo   Export it from the Godot editor ^(Project ^> Export ^> Windows^),
echo   or run Build.bat, or use Play-Source.bat to run the code directly.
echo.
pause
exit /b 1
