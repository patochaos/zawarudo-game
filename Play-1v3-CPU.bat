@echo off
REM Launch the current source straight into a four-fighter free-for-all:
REM keyboard Player 1 against three STANDARD CPUs on the first arena.
setlocal
cd /d "%~dp0"
call Play-Source.bat -- --vs-3-cpu
