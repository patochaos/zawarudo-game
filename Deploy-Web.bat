@echo off
setlocal
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Deploy-Web.ps1" %*
if errorlevel 1 goto :failed

echo.
echo   Deploy terminado.
echo.
pause
exit /b 0

:failed
echo.
echo   No se pudo publicar la build web.
echo.
pause
exit /b 1
