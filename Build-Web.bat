@echo off
setlocal
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Export-Web.ps1"
if errorlevel 1 goto :failed

echo.
echo   Build web lista en build\web
echo.
pause
exit /b 0

:failed
echo.
echo   No se pudo generar la build web.
echo.
pause
exit /b 1
