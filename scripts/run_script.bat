@echo off
setlocal enabledelayedexpansion

REM ==============================================================================
REM  Meerby: Minimal runner (ensure venv, install deps if needed, run script)
REM  WHAT THIS DOES:
REM    - Finds/creates a venv in the repo
REM    - Installs requirements.txt if present
REM    - Starts your Python script in the background
REM    - Writes the PID to app.pid
REM ==============================================================================

REM -----------------------------
REM CONFIG — EDIT ME
REM -----------------------------
set "REPO_DIR=%USERPROFILE%\Meerby-Solt-Reciever-Beacons"
set "SCRIPT_PATH=%REPO_DIR%\Socket_PC1.py"
set "VENV_DIR=%REPO_DIR%\venv"
set "PID_FILE=%REPO_DIR%\app.pid"
set "LOG_FILE=%REPO_DIR%\run.log"
set "SCRIPT_ARGS="

REM Auto-detect latest Python3 under %LocalAppData% (fallback to python on PATH)
set "PYTHON_EXE="
for /f "delims=" %%D in ('dir /b /ad "%USERPROFILE%\AppData\Local\Programs\Python\Python3*" 2^>nul ^| sort /r') do (
  if not defined PYTHON_EXE set "PYTHON_EXE=%USERPROFILE%\AppData\Local\Programs\Python\%%D\python.exe"
)
if not defined PYTHON_EXE set "PYTHON_EXE=python"

REM -----------------------------
REM PRECHECKS
REM -----------------------------
if not exist "%REPO_DIR%" (
  echo Repo dir not found: "%REPO_DIR%"
  exit /b 1
)
if not exist "%SCRIPT_PATH%" (
  echo Script not found: "%SCRIPT_PATH%"
  exit /b 1
)

REM -----------------------------
REM Ensure venv exists
REM -----------------------------
set "VENV_PY=%VENV_DIR%\Scripts\python.exe"
if not exist "%VENV_PY%" (
  echo [%DATE% %TIME%] Creating venv at "%VENV_DIR%" >> "%LOG_FILE%"
  "%PYTHON_EXE%" -m venv "%VENV_DIR%" >> "%LOG_FILE%" 2>&1
  if errorlevel 1 (
    echo Failed to create venv. See "%LOG_FILE%" for details.
    exit /b 1
  )
) else (
  echo [%DATE% %TIME%] Existing venv detected. >> "%LOG_FILE%"
)

REM -----------------------------
REM Upgrade pip & install requirements (if present)
REM -----------------------------
if exist "%VENV_PY%" (
  echo [%DATE% %TIME%] Upgrading pip... >> "%LOG_FILE%"
  "%VENV_PY%" -m pip install --upgrade pip >> "%LOG_FILE%" 2>&1

  if exist "%REPO_DIR%\requirements.txt" (
    echo [%DATE% %TIME%] Installing requirements... >> "%LOG_FILE%"
    "%VENV_PY%" -m pip install -r "%REPO_DIR%\requirements.txt" --no-cache-dir >> "%LOG_FILE%" 2>&1
  ) else (
    echo [%DATE% %TIME%] No requirements.txt, skipping deps. >> "%LOG_FILE%"
  )
) else (
  echo Could not find venv python at "%VENV_PY%".
  exit /b 1
)

REM -----------------------------
REM Start the app (detached) and write PID
REM -----------------------------
pushd "%REPO_DIR%" >nul

REM If an old PID exists, try to kill it gracefully (optional, safe if not running)
if exist "%PID_FILE%" (
  set /p OLD_PID=<"%PID_FILE%"
  if defined OLD_PID (
    tasklist /nh /fi "PID eq !OLD_PID!" | findstr "!OLD_PID!" >nul
    if not errorlevel 1 (
      echo [%DATE% %TIME%] Stopping previous PID !OLD_PID! >> "%LOG_FILE%"
      taskkill /PID !OLD_PID! /F /T >> "%LOG_FILE%" 2>&1
      timeout /t 1 >nul
    )
  )
)

echo [%DATE% %TIME%] Starting: "%VENV_PY%" "%SCRIPT_PATH%" %SCRIPT_ARGS% >> "%LOG_FILE%"

for /f %%i in ('powershell -NoProfile -Command ^
  "$p = Start-Process -FilePath ''%VENV_PY%'' -ArgumentList ''%SCRIPT_PATH% %SCRIPT_ARGS%'' -WorkingDirectory ''%REPO_DIR%'' -PassThru; $p.Id"') do (
  set "APP_PID=%%i"
)

if not defined APP_PID (
  echo Failed to start app (no PID captured). See "%LOG_FILE%".
  popd
  exit /b 1
)

echo %APP_PID% > "%PID_FILE%"
echo [%DATE% %TIME%] App started with PID %APP_PID% >> "%LOG_FILE%"

REM Optional quick health check
timeout /t 1 >nul
tasklist /nh /fi "PID eq %APP_PID%" | findstr "%APP_PID%" >nul
if errorlevel 1 (
  echo [%DATE% %TIME%] WARNING: Process %APP_PID% not detected after start. >> "%LOG_FILE%"
) else (
  echo [%DATE% %TIME%] Process %APP_PID% is running. >> "%LOG_FILE%"
)

popd >nul
exit /b 0
