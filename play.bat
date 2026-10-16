@echo off
cd /d "%~dp0"
where py >nul 2>&1
if errorlevel 1 goto use_python
py -3 "%~dp0play.py" %*
goto finished
:use_python
where python >nul 2>&1
if errorlevel 1 goto missing
python "%~dp0play.py" %*
goto finished
:missing
echo Python 3 is required. Install it from https://www.python.org/downloads/
pause
exit /b 1
:finished
set "game_exit=%errorlevel%"
if not "%game_exit%"=="0" pause
exit /b %game_exit%
