@echo off
setlocal enabledelayedexpansion

REM ===========================================
REM  Meerby: Start Task Script
REM ===========================================

REM -----------------------------
REM CONFIG — EDIT ME
REM -----------------------------

set "REPO_DIR=%USERPROFILE%\Meerby-Solt-Reciever-Beacons"
set "PID_FILE=%REPO_DIR%\app.pid"
set "STATE_DIR=%USERPROFILE%\Desktop\MeerbyUpdater"
set "LOG_FILE=%STATE_DIR%\deploy.log"

set "WINDOW_TITLE=MeerbySoltReceiver"

REM Auto-detect latest Python3* installation under %LocalAppData% (fallback to python on PATH)
set "PYTHON_EXE="

REM 1) System-wide
for /f "delims=" %%D in ('
  dir /b /ad "C:\Program Files\Python*" 2^>nul ^| sort /r
') do (
  if not defined PYTHON_EXE if exist "C:\Program Files\%%D\python.exe" (
    set "PYTHON_EXE=C:\Program Files\%%D\python.exe"
  )
)

REM 2) User-local installs (Latest first) — pick first real python(.exe/.3.exe)
if not defined PYTHON_EXE (
  for /f "delims=" %%D in ('
    dir /b /ad "%LOCALAPPDATA%\Programs\Python\Python3*" 2^>nul ^| sort /r
  ') do (
    for %%N in (python.exe python3.exe) do (
      if not defined PYTHON_EXE if exist "%LOCALAPPDATA%\Programs\Python\%%D\%%N" (
        set "PYTHON_EXE=%LOCALAPPDATA%\Programs\Python\%%D\%%N"
      )
    )
  )
)

REM 3) Last resort: name only (hope it's on PATH)
if not defined PYTHON_EXE set "PYTHON_EXE=python"


REM OPTIONAL: extra args to your script
set "SCRIPT_ARGS="

REM App entry point and venv
set "SCRIPT_PATH=%REPO_DIR%\Socket_PC1.py"
set "VENV_DIR=%REPO_DIR%\venv"
set "VENV_PY=%VENV_DIR%\Scripts\python.exe"

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

goto :ENSURE_AND_START_APP

:ENSURE_AND_START_APP
if not defined L_LOG_FILE    set "L_LOG_FILE=%LOG_FILE%"
if not defined L_VENV_DIR    set "L_VENV_DIR=%VENV_DIR%"
if not defined L_SCRIPT_PATH set "L_SCRIPT_PATH=%SCRIPT_PATH%"
if not defined L_SCRIPT_ARGS set "L_SCRIPT_ARGS=%SCRIPT_ARGS%"
if not defined L_PID_FILE    set "L_PID_FILE=%PID_FILE%"
if not defined L_REPO_DIR    set "L_REPO_DIR=%REPO_DIR%"
if not defined L_BASE_PYTHON set "L_BASE_PYTHON=%PYTHON_EXE%"

set "L_REQUIREMENTS=%L_REPO_DIR%\requirements.txt"
set "L_VENV_PY=%L_VENV_DIR%\Scripts\python.exe"

echo Ensuring virtual environment at %L_VENV_DIR% >> "%L_LOG_FILE%"
if not exist "%L_VENV_PY%" (
  if exist "%L_BASE_PYTHON%" (
    echo Creating venv... >> "%L_LOG_FILE%"
    "%L_BASE_PYTHON%" -m venv "%L_VENV_DIR%" >> "%L_LOG_FILE%" 2>&1
  ) else (
    echo WARNING: Base python exe not found at %L_BASE_PYTHON%. >> "%L_LOG_FILE%"
  )
) else (
  echo Existing venv detected. >> "%L_LOG_FILE%"
)

if exist "%L_VENV_PY%" (
  echo Upgrading pip... >> "%L_LOG_FILE%"
  "%L_VENV_PY%" -m pip install --upgrade pip >> "%L_LOG_FILE%" 2>&1
  if exist "%L_REQUIREMENTS%" (
    echo Installing requirements... >> "%L_LOG_FILE%"
    "%L_VENV_PY%" -m pip install -r "%L_REQUIREMENTS%" --no-cache-dir >> "%L_LOG_FILE%" 2>&1
  ) else (
    echo requirements.txt not found, skipping dependency install. >> "%L_LOG_FILE%"
  )
) else (
  echo WARNING: venv python missing; proceeding with fallback interpreter. >> "%L_LOG_FILE%"
  set "L_VENV_PY=%L_BASE_PYTHON%"
)

echo Starting app... >> "%L_LOG_FILE%"

REM Use PowerShell to start the process and capture the PID
set "POWERSHELL_CMD=powershell -NoProfile -Command "$p = Start-Process -FilePath '\""%L_VENV_PY%"\"' -ArgumentList '\""%L_SCRIPT_PATH%"\" %L_SCRIPT_ARGS%' -WindowStyle Normal -PassThru; echo $p.Id""
echo %POWERSHELL_CMD% >> "%L_LOG_FILE%"

REM Execute the PowerShell command and capture the output (the PID)
for /f %%i in ('%POWERSHELL_CMD%') do (
  set "APP_PID=%%i"
)

if defined APP_PID (
  echo %APP_PID% > "%L_PID_FILE%"
  echo App started with PID %APP_PID% >> "%L_LOG_FILE%"
) else (
  echo Failed to get PID for started app. >> "%L_LOG_FILE%"
)

timeout /t 2 >nul 2>&1
if exist "%L_PID_FILE%" (
  set /p APP_PID=<"%L_PID_FILE%"
  tasklist /nh /fi "PID eq !APP_PID!" | findstr /r ".*" >nul && (
    echo App process detected running. >> "%L_LOG_FILE%"
  ) || (
    echo WARNING: App process with PID !APP_PID! not detected after start. >> "%L_LOG_FILE%"
  )
) else (
  echo WARNING: PID file not created. Cannot verify if app is running. >> "%L_LOG_FILE%"
)
goto :EOF