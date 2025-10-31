@echo off
setlocal enabledelayedexpansion

REM ==============================================================================
REM Meerby Minimal Runner (Windows)
REM - Creates/uses venv
REM - Installs requirements.txt if present
REM - Starts Python script detached, writes PID to app.pid
REM - Logs immediately to %USERPROFILE%\Desktop\MeerbyLogs\log.txt
REM - Commands: start (default), stop, restart, status
REM ==============================================================================

REM -----------------------------
REM CONFIG — EDIT ME
REM -----------------------------
set "REPO_DIR=%USERPROFILE%\Meerby-Solt-Reciever-Beacons"
set "SCRIPT_PATH=%REPO_DIR%\Socket_PC1.py"
set "VENV_DIR=%REPO_DIR%\venv"
set "PID_FILE=%REPO_DIR%\app.pid"

REM Optional args to your script (or pass via CLI)
set "SCRIPT_ARGS="

REM Log to Desktop (always writable for the user)
set "LOG_DIR=%USERPROFILE%\Desktop\MeerbyLogs"
set "LOG_FILE=%LOG_DIR%\log.txt"

REM -----------------------------
REM INIT LOGGING
REM -----------------------------
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1
echo [%DATE% %TIME%] --- run_script.bat launched with args: %* --- >> "%LOG_FILE%"

REM -----------------------------
REM VALIDATE PATHS
REM -----------------------------
if not exist "%REPO_DIR%" (
  echo [%DATE% %TIME%] ERROR: Repo dir not found: "%REPO_DIR%" >> "%LOG_FILE%"
  echo Repo dir not found: "%REPO_DIR%"
  exit /b 1
)
if not exist "%SCRIPT_PATH%" (
  echo [%DATE% %TIME%] ERROR: Script not found: "%SCRIPT_PATH%" >> "%LOG_FILE%"
  echo Script not found: "%SCRIPT_PATH%"
  exit /b 1
)

REM -----------------------------
REM PYTHON AUTO-DETECTION (covers user/system installs, store stub)
REM -----------------------------
set "PYTHON_EXE="
set "PYTHON_EXE="

if exist "%ProgramFiles%\Python313\python.exe" set "PYTHON_EXE=%ProgramFiles%\Python313\python.exe"
if not defined PYTHON_EXE if exist "%ProgramFiles%\Python312\python.exe" set "PYTHON_EXE=%ProgramFiles%\Python312\python.exe"
if not defined PYTHON_EXE if exist "%USERPROFILE%\AppData\Local\Programs\Python\Python313\python.exe" set "PYTHON_EXE=%USERPROFILE%\AppData\Local\Programs\Python\Python313\python.exe"
if not defined PYTHON_EXE if exist "%USERPROFILE%\AppData\Local\Programs\Python\Python312\python.exe" set "PYTHON_EXE=%USERPROFILE%\AppData\Local\Programs\Python\Python312\python.exe"
if not defined PYTHON_EXE if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\python.exe" set "PYTHON_EXE=%LOCALAPPDATA%\Microsoft\WindowsApps\python.exe"

if not defined PYTHON_EXE (
  echo [%DATE% %TIME%] WARNING: Could not find Python automatically; falling back to PATH >> "%LOG_FILE%"
  set "PYTHON_EXE=python"
)

REM -----------------------------
REM VENV SETUP
REM -----------------------------
set "VENV_PY=%VENV_DIR%\Scripts\python.exe"
if not exist "%VENV_PY%" (
  echo [%DATE% %TIME%] Creating venv at "%VENV_DIR%" using "%PYTHON_EXE%" >> "%LOG_FILE%"
  "%PYTHON_EXE%" -m venv "%VENV_DIR%" >> "%LOG_FILE%" 2>&1
  if errorlevel 1 (
    echo [%DATE% %TIME%] FATAL: venv creation failed. >> "%LOG_FILE%"
    echo Failed to create venv. See log: "%LOG_FILE%"
    exit /b 1
  )
) else (
  echo [%DATE% %TIME%] Existing venv detected at "%VENV_DIR%" >> "%LOG_FILE%"
)

REM -----------------------------
REM PIP UPGRADE & REQUIREMENTS
REM -----------------------------
echo [%DATE% %TIME%] Upgrading pip... >> "%LOG_FILE%"
"%VENV_PY%" -m pip install --upgrade pip >> "%LOG_FILE%" 2>&1

if exist "%REPO_DIR%\requirements.txt" (
  echo [%DATE% %TIME%] Installing requirements from requirements.txt >> "%LOG_FILE%"
  "%VENV_PY%" -m pip install -r "%REPO_DIR%\requirements.txt" --no-cache-dir >> "%LOG_FILE%" 2>&1
) else (
  echo [%DATE% %TIME%] No requirements.txt found, skipping dependency install. >> "%LOG_FILE%"
)

REM -----------------------------
REM COMMAND DISPATCH
REM -----------------------------
set "CMD=%~1"
if not defined CMD set "CMD=start"

if /i "%CMD%"=="start"   goto :START_APP
if /i "%CMD%"=="stop"    goto :STOP_APP
if /i "%CMD%"=="restart" goto :RESTART_APP
if /i "%CMD%"=="status"  goto :STATUS_APP

echo Unknown command "%CMD%". Use: start|stop|restart|status
exit /b 2

REM -----------------------------
REM START
REM -----------------------------
:START_APP
pushd "%REPO_DIR%" >nul

REM If extra args were passed on CLI after the command, append them
set "EXTRA_ARGS="
if not "%~2"=="" (
  set "EXTRA_ARGS=%*"
  for /f "tokens=1,* delims= " %%A in ("%EXTRA_ARGS%") do set "EXTRA_ARGS=%%B"
)

REM Stop existing PID if running (safe no-op if not)
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

echo [%DATE% %TIME%] Starting: "%VENV_PY%" "%SCRIPT_PATH%" %SCRIPT_ARGS% %EXTRA_ARGS% >> "%LOG_FILE%"

for /f %%i in ('powershell -NoProfile -Command ^
  "$p = Start-Process -FilePath ''%VENV_PY%'' -ArgumentList ''%SCRIPT_PATH% %SCRIPT_ARGS% %EXTRA_ARGS%'' -WorkingDirectory ''%REPO_DIR%'' -PassThru; $p.Id"') do (
  set "APP_PID=%%i"
)

if not defined APP_PID (
  echo [%DATE% %TIME%] ERROR: Failed to capture PID after start. >> "%LOG_FILE%"
  echo Failed to start (no PID). See log: "%LOG_FILE%"
  popd >nul
  exit /b 1
)

echo %APP_PID% > "%PID_FILE%"
echo [%DATE% %TIME%] App started with PID %APP_PID% >> "%LOG_FILE%"

timeout /t 1 >nul
tasklist /nh /fi "PID eq %APP_PID%" | findstr "%APP_PID%" >nul
if errorlevel 1 (
  echo [%DATE% %TIME%] WARNING: Process %APP_PID% not detected after start. >> "%LOG_FILE%"
) else (
  echo [%DATE% %TIME%] Process %APP_PID% is running. >> "%LOG_FILE%"
)

popd >nul
exit /b 0

REM -----------------------------
REM STOP
REM -----------------------------
:STOP_APP
if not exist "%PID_FILE%" (
  echo No PID file found at "%PID_FILE%".
  echo [%DATE% %TIME%] stop: no PID file >> "%LOG_FILE%"
  exit /b 0
)
set /p KILL_PID=<"%PID_FILE%"
if not defined KILL_PID (
  echo PID file empty; nothing to stop.
  echo [%DATE% %TIME%] stop: empty PID file >> "%LOG_FILE%"
  del /q "%PID_FILE%" >nul 2>&1
  exit /b 0
)
tasklist /nh /fi "PID eq %KILL_PID%" | findstr "%KILL_PID%" >nul
if errorlevel 1 (
  echo Process %KILL_PID% not running.
  echo [%DATE% %TIME%] stop: PID %KILL_PID% not running >> "%LOG_FILE%"
  del /q "%PID_FILE%" >nul 2>&1
  exit /b 0
)
echo Stopping PID %KILL_PID%...
echo [%DATE% %TIME%] Stopping PID %KILL_PID% >> "%LOG_FILE%"
taskkill /PID %KILL_PID% /F /T >> "%LOG_FILE%" 2>&1
del /q "%PID_FILE%" >nul 2>&1
exit /b 0

REM -----------------------------
REM RESTART
REM -----------------------------
:RESTART_APP
call "%~f0" stop
call "%~f0" start %*
exit /b %ERRORLEVEL%

REM -----------------------------
REM STATUS
REM -----------------------------
:STATUS_APP
if not exist "%PID_FILE%" (
  echo Status: not running (no PID file).
  exit /b 0
)
set /p S_PID=<"%PID_FILE%"
if not defined S_PID (
  echo Status: not running (empty PID file).
  exit /b 0
)
tasklist /nh /fi "PID eq %S_PID%" | findstr "%S_PID%" >nul
if errorlevel 1 (
  echo Status: not running (PID %S_PID% not found).
) else (
  echo Status: running (PID %S_PID%).
)
exit /b 0
