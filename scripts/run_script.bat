@echo off
setlocal enabledelayedexpansion

REM ==============================================================================
REM  Meerby: Script launcher
REM ==============================================================================

REM -----------------------------
REM CONFIG — EDIT IF NEEDED
REM -----------------------------
set "REPO_DIR=%USERPROFILE%\Meerby-Solt-Reciever-Beacons"
set "STATE_DIR=%USERPROFILE%\Desktop\MeerbyUpdater"
set "LOG_FILE=%STATE_DIR%\deploy.log"
set "PID_FILE=%REPO_DIR%\app.pid"

REM App process settings (currently not used, kept for future)
set "WINDOW_TITLE=MeerbySoltReceiver"

REM Python detection (prefer Program Files, then local user, then PATH)
set "PYTHON_EXE="

REM 1) System-wide (C:\Program Files\Python*)
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

REM 3) System-wide 32-bit (C:\Program Files (x86)\Python*)
if not defined PYTHON_EXE (
  for /f "delims=" %%D in ('
    dir /b /ad "C:\Program Files (x86)\Python*" 2^>nul ^| sort /r
  ') do (
    if not defined PYTHON_EXE set "PYTHON_EXE=C:\Program Files (x86)\%%D\python.exe"
  )
)

REM 4) Fallback: PATH (ignore WindowsApps shim)
if not defined PYTHON_EXE (
  for /f "delims=" %%P in ('where python.exe 2^>nul') do (
    echo "%%P" | findstr /i /c:"\WindowsApps\python.exe" >nul || (
      if not defined PYTHON_EXE set "PYTHON_EXE=%%P"
    )
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

REM Clear any stale PID file from previous runs
del "%PID_FILE%" >nul 2>&1

REM Default path: ensure and start
goto :ENSURE_AND_START_APP

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

REM --------------------------------------------------------------------------
REM Start Python, capture its PID
REM --------------------------------------------------------------------------
set "PY_PID="

for /f %%P in ('
  powershell -NoProfile -Command ^
    "$p = Start-Process -FilePath ''%RUN_PY%'' -ArgumentList ''\"%SCRIPT_PATH%\" %SCRIPT_ARGS%'' -PassThru; $p.Id"
') do (
  set "PY_PID=%%P"
)

if not defined PY_PID (
  echo [%DATE% %TIME%] ERROR: Failed to start Python or capture PID. >> "%LOG_FILE%"
  exit /b 1
)

echo [%DATE% %TIME%] Python started with PID !PY_PID! >> "%LOG_FILE%"
> "%PID_FILE%" echo !PY_PID!

REM Wait for the Python process to exit
powershell -NoProfile -Command "Wait-Process -Id !PY_PID!"

set "EXITCODE=%ERRORLEVEL%"
echo [%DATE% %TIME%] Python process !PY_PID! exited with code !EXITCODE!. >> "%LOG_FILE%"

REM Remove PID file on exit
del "%PID_FILE%" >nul 2>&1

exit /b !EXITCODE!
