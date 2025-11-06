@echo off
setlocal enabledelayedexpansion

REM ==============================================================================
REM  Meerby: Local launcher (no Git). Health-check + start/stop/restart.
REM  Usage:
REM     run_script.bat           -> ensure running (start if not)
REM     run_script.bat restart   -> force restart
REM     run_script.bat stop      -> stop if running
REM ==============================================================================

REM -----------------------------
REM CONFIG — EDIT IF NEEDED
REM -----------------------------
set "REPO_DIR=%USERPROFILE%\Meerby-Solt-Reciever-Beacons"
set "STATE_DIR=%USERPROFILE%\Desktop\MeerbyUpdater"
set "LOG_FILE=%STATE_DIR%\deploy.log"
set "PID_FILE=%REPO_DIR%\app.pid"

REM App process settings
set "WINDOW_TITLE=MeerbySoltReceiver"

REM Python detection (prefer local user install, then Program Files)
set "PYTHON_EXE="

REM 1) User-local installs (Latest first)
for /f "delims=" %%D in ('
  dir /b /ad "%LOCALAPPDATA%\Programs\Python\Python3*" 2^>nul ^| sort /r
') do (
  if not defined PYTHON_EXE set "PYTHON_EXE=%LOCALAPPDATA%\Programs\Python\%%D\python.exe"
)

REM 2) System-wide (C:\Program Files\Python*)
if not defined PYTHON_EXE (
  for /f "delims=" %%D in ('
    dir /b /ad "C:\Program Files\Python*" 2^>nul ^| sort /r
  ') do (
    if not defined PYTHON_EXE set "PYTHON_EXE=C:\Program Files\%%D\python.exe"
  )
)

REM 3) System-wide 32-bit (C:\Program Files (x86)\Python*)
if not defined PYTHON_EXE (
  for /f "delims=" %%D in ('
    dir /b /ad "C:\Program Files (x86)\Python*" 2^>nul ^| sort /r
  ') do (
    if not defined PYTHON_EXE set "PYTHON_EXE=C:\Program Files (x86)\%%D\python.exe"
  )
)

REM 4) Fallback: any python.exe found on disk/PATH via WHERE
if not defined PYTHON_EXE (
  for /f "delims=" %%P in ('where python.exe 2^>nul') do (
    if not defined PYTHON_EXE set "PYTHON_EXE=%%P"
  )
)

REM 5) Last resort: name only (hope it's on PATH)
if not defined PYTHON_EXE set "PYTHON_EXE=python"

REM App entry point and venv
set "SCRIPT_PATH=%REPO_DIR%\Socket_PC1.py"
set "VENV_DIR=%REPO_DIR%\venv"
set "VENV_PY=%VENV_DIR%\Scripts\python.exe"

REM Optional args to your script
set "SCRIPT_ARGS="

REM -----------------------------
REM INIT: folders & log header
REM -----------------------------
if not exist "%STATE_DIR%" mkdir "%STATE_DIR%" >nul 2>&1
if not exist "%REPO_DIR%" (
  echo [%DATE% %TIME%] ERROR: App folder not found at "%REPO_DIR%". >> "%LOG_FILE%"
  echo ERROR: App folder not found at "%REPO_DIR%".
  exit /b 1
)
echo [%DATE% %TIME%] --- launcher start --- >> "%LOG_FILE%"

REM -----------------------------
REM ARG PARSING
REM -----------------------------
if /i "%~1"=="restart" goto :DO_RESTART
if /i "%~1"=="stop"    goto :DO_STOP

REM Default path: health check + ensure running
goto :HEALTHCHECK_AND_START


:DO_STOP
call :STOP_APP
exit /b %ERRORLEVEL%


:DO_RESTART
call :STOP_APP
call :ENSURE_AND_START_APP
exit /b %ERRORLEVEL%


:HEALTHCHECK_AND_START
REM Check PID file; if running, do nothing; else start it
set "PID_IS_RUNNING="
if exist "%PID_FILE%" (
  set /p APP_PID=<"%PID_FILE%"
  if defined APP_PID (
    tasklist /nh /fi "PID eq !APP_PID!" | findstr "!APP_PID!" >nul && set "PID_IS_RUNNING=true"
  )
)

if defined PID_IS_RUNNING (
  echo [%DATE% %TIME%] Health check: App already running with PID !APP_PID!. >> "%LOG_FILE%"
  exit /b 0
) else (
  echo [%DATE% %TIME%] App not running; attempting start. >> "%LOG_FILE%"
  call :ENSURE_AND_START_APP
  exit /b %ERRORLEVEL%
)

REM ==============================================================================
REM FUNCTIONS
REM ==============================================================================

:STOP_APP
echo [%DATE% %TIME%] Stopping existing app (PID from file)... >> "%LOG_FILE%"
if exist "%PID_FILE%" (
  set /p APP_PID=<"%PID_FILE%"
  if defined APP_PID (
    echo Attempting to kill PID !APP_PID!. >> "%LOG_FILE%"
    taskkill /PID !APP_PID! /F /T >> "%LOG_FILE%" 2>&1
    del /q "%PID_FILE%" >nul 2>&1
  ) else (
    echo PID file empty; nothing to kill. >> "%LOG_FILE%"
  )
) else (
  echo PID file not found; nothing to kill. >> "%LOG_FILE%"
)
timeout /t 1 >nul 2>&1
exit /b 0


:ENSURE_AND_START_APP
REM Ensure venv, pip, requirements; then start app and record PID
if not exist "%SCRIPT_PATH%" (
  echo [%DATE% %TIME%] ERROR: Script not found at "%SCRIPT_PATH%". >> "%LOG_FILE%"
  echo ERROR: Script not found at "%SCRIPT_PATH%".
  exit /b 1
)

REM Create venv if missing
if not exist "%VENV_PY%" (
  if exist "%PYTHON_EXE%" (
    echo [%DATE% %TIME%] Creating venv at "%VENV_DIR%"... >> "%LOG_FILE%"
    "%PYTHON_EXE%" -m venv "%VENV_DIR%" >> "%LOG_FILE%" 2>&1
  ) else (
    echo [%DATE% %TIME%] WARNING: Base Python not found at %PYTHON_EXE%. >> "%LOG_FILE%"
  )
) else (
  echo [%DATE% %TIME%] Existing venv detected. >> "%LOG_FILE%"
)

REM Use venv python if exists; else fallback to base python on PATH
set "RUN_PY=%VENV_PY%"
if not exist "%RUN_PY%" set "RUN_PY=%PYTHON_EXE%"

REM Upgrade pip and install requirements if present
if exist "%RUN_PY%" (
  echo [%DATE% %TIME%] Upgrading pip... >> "%LOG_FILE%"
  "%RUN_PY%" -m pip install --upgrade pip >> "%LOG_FILE%" 2>&1
  if exist "%REPO_DIR%\requirements.txt" (
    echo [%DATE% %TIME%] Installing requirements... >> "%LOG_FILE%"
    "%RUN_PY%" -m pip install -r "%REPO_DIR%\requirements.txt" --no-cache-dir >> "%LOG_FILE%" 2>&1
  ) else (
    echo [%DATE% %TIME%] requirements.txt not found; skipping dependencies. >> "%LOG_FILE%"
  )
) else (
  echo [%DATE% %TIME%] WARNING: No Python interpreter found; cannot start app. >> "%LOG_FILE%"
  exit /b 1
)

REM Start the app with PowerShell to capture PID cleanly
set "POWERSHELL_CMD=powershell -NoProfile -Command "$p = Start-Process -FilePath '\""%RUN_PY%"\"' -ArgumentList '\""%SCRIPT_PATH%"\" %SCRIPT_ARGS%' -WindowStyle Hidden -PassThru; echo $p.Id""
echo %POWERSHELL_CMD% >> "%LOG_FILE%"

for /f %%i in ('%POWERSHELL_CMD%') do (
  set "APP_PID=%%i"
)

if defined APP_PID (
  > "%PID_FILE%" echo %APP_PID%
  echo [%DATE% %TIME%] App started with PID %APP_PID%. >> "%LOG_FILE%"
) else (
  echo [%DATE% %TIME%] ERROR: Failed to retrieve PID after start. >> "%LOG_FILE%"
  exit /b 1
)

timeout /t 2 >nul 2>&1
if exist "%PID_FILE%" (
  set /p APP_PID=<"%PID_FILE%"
  tasklist /nh /fi "PID eq !APP_PID!" | findstr /r ".*" >nul && (
    echo [%DATE% %TIME%] App process detected running. >> "%LOG_FILE%"
  ) || (
    echo [%DATE% %TIME%] WARNING: PID !APP_PID! not detected after start. >> "%LOG_FILE%"
  )
) else (
  echo [%DATE% %TIME%] WARNING: PID file not found after start. >> "%LOG_FILE%"
)

exit /b 0
