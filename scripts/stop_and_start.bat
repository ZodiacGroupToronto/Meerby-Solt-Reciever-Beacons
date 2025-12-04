@echo off
setlocal enabledelayedexpansion


REM ==============================================================================
REM  Meerby: Script launcher
REM ==============================================================================


@REM REM -----------------------------
@REM REM CONFIG — EDIT ME
@REM REM -----------------------------
@REM set "REPO_DIR=%USERPROFILE%\Meerby-Solt-Reciever-Beacons"
@REM set "PID_FILE=%REPO_DIR%\app.pid"
@REM set "STOP_SCRIPT=%REPO_DIR%\scripts\stop_task.bat"
@REM set "START_SCRIPT=%REPO_DIR%\scripts\start_task.bat"
set "STOP_SCRIPT=%~dp0stop_task.bat"
set "START_SCRIPT=%~dp0start_task.bat"
call "%STOP_SCRIPT%"
call "%START_SCRIPT%"
@REM REM Where to store state/logs OUTSIDE the repo so they survive resets
@REM set "STATE_DIR=%USERPROFILE%\Desktop\MeerbyUpdater"
@REM set "LOG_FILE=%STATE_DIR%\deploy.log"

@REM REM Your app process settings (adjust to your environment)
@REM set "WINDOW_TITLE=MeerbySoltReceiver"

@REM REM Auto-detect latest Python3* installation under %LocalAppData% (fallback to python on PATH)
@REM set "PYTHON_EXE="

@REM REM 1) System-wide
@REM for /f "delims=" %%D in ('
@REM   dir /b /ad "C:\Program Files\Python*" 2^>nul ^| sort /r
@REM ') do (
@REM   if not defined PYTHON_EXE if exist "C:\Program Files\%%D\python.exe" (
@REM     set "PYTHON_EXE=C:\Program Files\%%D\python.exe"
@REM   )
@REM )

@REM REM 2) User-local installs (Latest first) — pick first real python(.exe/.3.exe)
@REM if not defined PYTHON_EXE (
@REM   for /f "delims=" %%D in ('
@REM     dir /b /ad "%LOCALAPPDATA%\Programs\Python\Python3*" 2^>nul ^| sort /r
@REM   ') do (
@REM     for %%N in (python.exe python3.exe) do (
@REM       if not defined PYTHON_EXE if exist "%LOCALAPPDATA%\Programs\Python\%%D\%%N" (
@REM         set "PYTHON_EXE=%LOCALAPPDATA%\Programs\Python\%%D\%%N"
@REM       )
@REM     )
@REM   )
@REM )

@REM REM 5) Last resort: name only (hope it's on PATH)
@REM if not defined PYTHON_EXE set "PYTHON_EXE=python"

@REM set "SCRIPT_PATH=%REPO_DIR%\Socket_PC1.py"
@REM REM NEW: default virtual environment directory inside the repo (can change)
@REM set "VENV_DIR=%REPO_DIR%\venv"

@REM REM OPTIONAL: extra args to your script
@REM set "SCRIPT_ARGS="

@REM REM App entry point and venv

@REM set "SCRIPT_PATH=%REPO_DIR%\Socket_PC1.py"
@REM set "VENV_DIR=%REPO_DIR%\venv"
@REM set "VENV_PY=%VENV_DIR%\Scripts\python.exe"

@REM REM -----------------------------
@REM REM INIT: folders & log header
@REM REM -----------------------------

@REM if not exist "%STATE_DIR%" mkdir "%STATE_DIR%" >nul 2>&1
@REM if not exist "%REPO_DIR%" (
@REM   echo [%DATE% %TIME%] ERROR: App folder not found at "%REPO_DIR%". >> "%LOG_FILE%"
@REM   echo ERROR: App folder not found at "%REPO_DIR%".
@REM   exit /b 1
@REM )
@REM echo [%DATE% %TIME%] --- launcher start --- >> "%LOG_FILE%"


@REM @REM REM Clear any stale PID file from previous runs
@REM @REM del "%PID_FILE%" >nul 2>&1

@REM REM Default path: ensure and start
@REM goto :ENSURE_AND_START_APP

@REM :ENSURE_AND_START_APP
@REM set "L_LOG_FILE=%L_LOG_FILE%"
@REM if not defined L_LOG_FILE set "L_LOG_FILE=%LOG_FILE%"
@REM set "L_VENV_DIR=%U_VENV_DIR%"
@REM if not defined L_VENV_DIR set "L_VENV_DIR=%VENV_DIR%"
@REM set "L_SCRIPT_PATH=%U_SCRIPT_PATH%"
@REM if not defined L_SCRIPT_PATH set "L_SCRIPT_PATH=%SCRIPT_PATH%"
@REM set "L_SCRIPT_ARGS=%U_SCRIPT_ARGS%"
@REM if not defined L_SCRIPT_ARGS set "L_SCRIPT_ARGS=%SCRIPT_ARGS%"
@REM set "L_PID_FILE=%L_PID_FILE%"
@REM if not defined L_PID_FILE set "L_PID_FILE=%PID_FILE%"
@REM set "L_REPO_DIR=%U_REPO_DIR%"
@REM if not defined L_REPO_DIR set "L_REPO_DIR=%REPO_DIR%"
@REM set "L_REQUIREMENTS=%L_REPO_DIR%\requirements.txt"
@REM set "L_BASE_PYTHON=%U_PYTHON_EXE%"
@REM if not defined L_BASE_PYTHON set "L_BASE_PYTHON=%PYTHON_EXE%"
@REM set "L_VENV_PY=%L_VENV_DIR%\Scripts\python.exe"

@REM call :STOP_APP

@REM echo Ensuring virtual environment at %L_VENV_DIR% >> "%L_LOG_FILE%"
@REM if not exist "%L_VENV_PY%" (
@REM   if exist "%L_BASE_PYTHON%" (
@REM     echo Creating venv... >> "%L_LOG_FILE%"
@REM     "%L_BASE_PYTHON%" -m venv "%L_VENV_DIR%" >> "%L_LOG_FILE%" 2>&1
@REM   ) else (
@REM     echo WARNING: Base python exe not found at %L_BASE_PYTHON%. >> "%L_LOG_FILE%"
@REM   )
@REM ) else (
@REM   echo Existing venv detected. >> "%L_LOG_FILE%"
@REM )

@REM if exist "%L_VENV_PY%" (
@REM   echo Upgrading pip... >> "%L_LOG_FILE%"
@REM   "%L_VENV_PY%" -m pip install --upgrade pip >> "%L_LOG_FILE%" 2>&1
@REM   if exist "%L_REQUIREMENTS%" (
@REM     echo Installing requirements... >> "%L_LOG_FILE%"
@REM     "%L_VENV_PY%" -m pip install -r "%L_REQUIREMENTS%" --no-cache-dir >> "%L_LOG_FILE%" 2>&1
@REM   ) else (
@REM     echo requirements.txt not found, skipping dependency install. >> "%L_LOG_FILE%"
@REM   )
@REM ) else (
@REM   echo WARNING: venv python missing; proceeding with fallback interpreter. >> "%L_LOG_FILE%"
@REM   set "L_VENV_PY=%L_BASE_PYTHON%"
@REM )

@REM echo Starting app... >> "%L_LOG_FILE%"

@REM REM Use PowerShell to start the process and capture the PID
@REM set "POWERSHELL_CMD=powershell -NoProfile -Command "$p = Start-Process -FilePath '\""%L_VENV_PY%"\"' -ArgumentList '\""%L_SCRIPT_PATH%"\" %L_SCRIPT_ARGS%' -WindowStyle Normal -PassThru; echo $p.Id""
@REM echo %POWERSHELL_CMD% >> "%L_LOG_FILE%"

@REM REM Execute the PowerShell command and capture the output (the PID)
@REM for /f %%i in ('%POWERSHELL_CMD%') do (
@REM   set "APP_PID=%%i"
@REM )

@REM if defined APP_PID (
@REM   echo %APP_PID% > "%L_PID_FILE%"
@REM   echo App started with PID %APP_PID% >> "%L_LOG_FILE%"
@REM ) else (
@REM   echo Failed to get PID for started app. >> "%L_LOG_FILE%"
@REM )

@REM timeout /t 2 >nul 2>&1
@REM if exist "%L_PID_FILE%" (
@REM   set /p APP_PID=<"%L_PID_FILE%"
@REM   tasklist /nh /fi "PID eq !APP_PID!" | findstr /r ".*" >nul && (
@REM     echo App process detected running. >> "%L_LOG_FILE%"
@REM   ) || (
@REM     echo WARNING: App process with PID !APP_PID! not detected after start. >> "%L_LOG_FILE%"
@REM   )
@REM ) else (
@REM   echo WARNING: PID file not created. Cannot verify if app is running. >> "%L_LOG_FILE%"
@REM )
@REM goto :EOF