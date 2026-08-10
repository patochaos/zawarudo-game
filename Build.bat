@echo off
REM ---------------------------------------------------------------------------
REM  ZAWARUDO - export Windows + Web and package both for itch.io.
REM  Needs Godot 4.7 with export templates installed.
REM ---------------------------------------------------------------------------
setlocal
cd /d "%~dp0"

REM Resolve to a full path -- cmd refuses to `call` a quoted bare PATH name.
set "GODOT="
for /f "delims=" %%i in ('where godot 2^>nul') do if not defined GODOT set "GODOT=%%i"
if not defined GODOT if exist "D:\Godot\godot.cmd" set "GODOT=D:\Godot\godot.cmd"
if not defined GODOT goto :nogodot

if not exist "build\itch\windows" mkdir "build\itch\windows"
if not exist "build\itch\web" mkdir "build\itch\web"

echo.
echo [1/3] Exporting Windows...
call "%GODOT%" --headless --export-release "Windows" "build/itch/windows/ZAWARUDO.exe" >nul
if errorlevel 1 goto :failed

echo [2/3] Exporting Web...
call "%GODOT%" --headless --export-release "Web" "build/itch/web/index.html" >nul
if errorlevel 1 goto :failed
del /q "build\itch\web\*.import" >nul 2>&1

echo [3/3] Packaging zips...
copy /y "itch\WINDOWS-README.txt" "build\itch\windows\README.txt" >nul
powershell -NoProfile -Command "Compress-Archive -Path 'build/itch/web/*' -DestinationPath 'build/itch/ZAWARUDO-web.zip' -Force"
if errorlevel 1 goto :failed
powershell -NoProfile -Command "Compress-Archive -Path 'build/itch/windows/*' -DestinationPath 'build/itch/ZAWARUDO-windows.zip' -Force"
if errorlevel 1 goto :failed

echo.
echo   Done. Upload-ready:
echo     build\itch\ZAWARUDO-web.zip       ^(itch: HTML5, 1280x720, Click to Play^)
echo     build\itch\ZAWARUDO-windows.zip   ^(itch: Windows download^)
echo.
pause
exit /b 0

:nogodot
echo.
echo   Godot was not found on PATH.
echo   Add the Godot 4.7 folder to PATH, or edit the hard-coded path in this file.
echo.
pause
exit /b 1

:failed
echo.
echo   Export failed. Check that Godot's export templates for 4.7.1 are installed
echo   ^(Editor ^> Manage Export Templates^).
echo.
pause
exit /b 1
