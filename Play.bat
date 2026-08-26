@echo off
REM ---------------------------------------------------------------------------
REM  ZAWARUDO - launch the latest local source through Godot.
REM  No export or packaged build is required.
REM ---------------------------------------------------------------------------
call "%~dp0Play-Source.bat" %*
exit /b %errorlevel%
