@echo off
REM Launch the current source with the simplified Gilded Executor on Player 1.
REM Other fighters intentionally retain the legacy renderer until their own
REM silhouette-approved arena sprites exist.
setlocal
cd /d "%~dp0"
call Play-Source.bat -- --simplified-fighter-proto
