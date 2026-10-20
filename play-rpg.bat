@echo off
call "%~dp0play.bat" --game rpg %*
exit /b %errorlevel%
