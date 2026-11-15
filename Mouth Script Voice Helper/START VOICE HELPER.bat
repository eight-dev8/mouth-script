@echo off
title Mouth Script voice helper
cd /d "%~dp0"

set PY=
where py >nul 2>&1 && set PY=py
if not defined PY (
    where python >nul 2>&1 && set PY=python
)
if not defined PY (
    echo Python isn't installed or isn't on PATH.
    echo Install Python 3.10 or newer from python.org and tick "Add Python to PATH".
    pause
    exit /b
)

if not exist "installed.txt" (
    echo First time setup: installing what the voice helper needs. This only happens once.
    %PY% -m pip install --upgrade pip
    %PY% -m pip install -r requirements.txt
    if errorlevel 1 (
        echo.
        echo Installing failed. Check your internet connection and try again.
        pause
        exit /b
    )
    echo done> installed.txt
)

%PY% voice_helper.py
pause
