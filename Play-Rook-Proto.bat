@echo off
REM Launch the current source with The Rook selected for Player 1 and the
REM versioned animated arena-sprite pipeline enabled. Other roster members keep
REM their own existing renderer; the Rook art is never recolored onto them.
setlocal
cd /d "%~dp0"
call Play-Source.bat -- --simplified-fighter-proto --rook-proto
