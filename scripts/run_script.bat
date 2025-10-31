@echo off
setlocal enabledelayedexpansion

REM ==============================================================================
REM Meerby: Run Python via BAT (no venv)
REM - Prefers py launcher (-3) else falls back to first python.exe on PATH
REM - Sets working directory
REM - Logs stdout/stderr
REM - Pass-through args supported
REM ==============================================================================

REM --- CONFIG (edit if you want fixed paths) ---
REM If this .bat lives in ...\Meerby-Solt-Reciever-Beacons\scripts\
REM then the repo folder is one level up:
set "REPO_DIR=%~dp0.."
set "SCRIPT_PATH=%REPO_DIR%\Socket_PC1.py"

REM Log goes to repo\logs\run.log (change if you like)
set "LOG_DIR=%REPO_DIR%\logs"
set "LOG_FILE=%LOG_DIR%\run.log"

REM --- Ensure paths exist ---
if not exist "%REPO_DIR%" (
  echo [%DATE% %TIME%] ERROR: Repo folder not found: "%REPO_DIR%"
  exit /b 1
)
if not exist "%SCRIPT_PATH%" (
  echo [%DATE% %TIME%] ERROR: Script not found: "%SCRIPT_PATH%"
  exit /b 1
)
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1

echo.>>"%LOG_FILE%"
echo [%DATE% %TIME%] --- run_python_task.bat start --- >>"%LOG_FILE%"
echo [%DATE% %TIME%] CWD will be: "%REPO_DIR%" >>"%LOG_FILE%"
echo [%DATE% %TIME%] Script: "%SCRIPT_PATH%" >>"%LOG_FILE%"
echo [%DATE% %TIME%] Args: %* >>"%LOG_FILE%"

REM --- Find Python (prefer py.exe -3) ---
set "PY_EXE="
set "PY_ARGS="

if exist "%SystemRoot%\py.exe" (
  set "PY_EXE=%SystemRoot%\py.exe"
  set "PY_ARGS=-3"
) else (
  for /f "delims=" %%P in ('where python 2^>nul') do (
    if not defined PY_EXE set "PY_EXE=%%~P"
  )
)

if not defined PY_EXE (
  echo [%DATE% %TIME%] FATAL: No Python found (neither py.exe nor python on PATH). >>"%LOG_FILE%"
  exit /b 1
)

echo [%DATE% %TIME%] Using Python: "%PY_EXE%" %PY_ARGS% >>"%LOG_FILE%"

REM --- Run the script (capture stdout/stderr) ---
pushd "%REPO_DIR%" >nul
"%PY_EXE%" %PY_ARGS% "%SCRIPT_PATH%" %*  >>"%LOG_FILE%" 2>&1
set "RC=%ERRORLEVEL%"
popd >nul

echo [%DATE% %TIME%] Script exit code: %RC% >>"%LOG_FILE%"
echo [%DATE% %TIME%] --- run_python_task.bat end --- >>"%LOG_FILE%"

exit /b %RC%