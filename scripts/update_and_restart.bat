@echo off
setlocal enabledelayedexpansion

if /i "%~1"=="run-update" goto RUN_UPDATE_MODE

REM ==============================================================================
REM  Meerby: Auto-update & restart
REM ==============================================================================

REM -----------------------------------------------------------------------
REM CONFIG
REM -----------------------------------------------------------------------
set "REPO_DIR=C:\ProgramData\MeerbyPCScript\app\Meerby-Solt-Reciever-Beacons-edge-computing-encryption"
set "BRANCH=edge-computing-encryption"

REM All state and logs under ProgramData — NOT %USERPROFILE%
set "STATE_DIR=C:\ProgramData\MeerbyPCScript"
set "DEPLOYED_FILE=%STATE_DIR%\last_deployed_commit.txt"
set "LOG_FILE=%STATE_DIR%\logs\deploy.log"
set "PID_FILE=%REPO_DIR%\app.pid"

set "WINDOW_TITLE=MeerbySoltReceiver"

REM -----------------------------------------------------------------------
REM Python: system-wide paths only (no per-user AppData)
REM setup.ps1 installs Python to "C:\Program Files\python.exe"
REM -----------------------------------------------------------------------
set "PYTHON_EXE="
if exist "C:\Program Files\python.exe"  set "PYTHON_EXE=C:\Program Files\python.exe"
if not defined PYTHON_EXE if exist "C:\Python312\python.exe" set "PYTHON_EXE=C:\Python312\python.exe"
if not defined PYTHON_EXE if exist "C:\Python311\python.exe" set "PYTHON_EXE=C:\Python311\python.exe"
if not defined PYTHON_EXE if exist "C:\Python310\python.exe" set "PYTHON_EXE=C:\Python310\python.exe"
if not defined PYTHON_EXE (
    echo WARNING: Python not found in system paths, falling back to PATH. >> "%LOG_FILE%"
    set "PYTHON_EXE=python"
)

set "SCRIPT_PATH=%REPO_DIR%\Socket_PC1.py"
set "VENV_DIR=%REPO_DIR%\venv"
set "SCRIPT_ARGS="

set "REMOTE_URL=https://github.com/ZodiacGroupToronto/Meerby-Solt-Reciever-Beacons.git"

REM -----------------------------------------------------------------------
REM INIT
REM -----------------------------------------------------------------------
if not exist "%STATE_DIR%\logs" mkdir "%STATE_DIR%\logs" >nul 2>&1
echo [%DATE% %TIME%] --- updater start --- >> "%LOG_FILE%"

REM -----------------------------------------------------------------------
REM PRECHECK
REM -----------------------------------------------------------------------
if not exist "%REPO_DIR%\.git" (
    echo Repo not found at "%REPO_DIR%". Clone first: >> "%LOG_FILE%"
    echo   git clone "%REMOTE_URL%" "%REPO_DIR%" >> "%LOG_FILE%"
    echo Repo not found. See deploy.log for details.
    exit /b 1
)

pushd "%REPO_DIR%" || (echo Failed to cd to repo >> "%LOG_FILE%" & exit /b 1)

REM -----------------------------------------------------------------------
REM STEP 1: Fetch
REM -----------------------------------------------------------------------
git fetch origin %BRANCH% --quiet
if errorlevel 1 (echo git fetch failed >> "%LOG_FILE%" & popd & exit /b 1)

REM -----------------------------------------------------------------------
REM STEP 2: Compare hashes
REM -----------------------------------------------------------------------
for /f "usebackq" %%h in (`git rev-parse HEAD`) do set "LOCAL_HASH=%%h"
for /f "usebackq" %%h in (`git rev-parse origin/%BRANCH%`) do set "REMOTE_HASH=%%h"

if "%LOCAL_HASH%"==""  (echo Failed to get LOCAL_HASH  >> "%LOG_FILE%" & popd & exit /b 1)
if "%REMOTE_HASH%"=="" (echo Failed to get REMOTE_HASH >> "%LOG_FILE%" & popd & exit /b 1)

REM -----------------------------------------------------------------------
REM STEP 3: No change — ensure app is running
REM -----------------------------------------------------------------------
if "%LOCAL_HASH%"=="%REMOTE_HASH%" (
    echo No change. local=%LOCAL_HASH% >> "%LOG_FILE%"
    set "PID_IS_RUNNING="
    if exist "%PID_FILE%" (
        set /p APP_PID=<"%PID_FILE%"
        if defined APP_PID (
            tasklist /nh /fi "PID eq !APP_PID!" | findstr "!APP_PID!" >nul && set "PID_IS_RUNNING=true"
        )
    )
    if defined PID_IS_RUNNING (
        echo Health check: app running PID=!APP_PID! >> "%LOG_FILE%"
    ) else (
        echo App not running, starting... >> "%LOG_FILE%"
        call :ENSURE_AND_START_APP
    )
    popd & exit /b 0
)

echo Change detected: %LOCAL_HASH% -^> %REMOTE_HASH% >> "%LOG_FILE%"

REM -----------------------------------------------------------------------
REM STEP 4: Self-copy to STATE_DIR and run update from there
REM -----------------------------------------------------------------------
set "TEMP_RUN=%STATE_DIR%\meerby_update_runner.bat"
copy /Y "%~f0" "%TEMP_RUN%" >nul
if errorlevel 1 (echo Failed to copy self >> "%LOG_FILE%" & popd & exit /b 1)

call "%TEMP_RUN%" run-update "%REPO_DIR%" "%BRANCH%" "%REMOTE_HASH%" "%WINDOW_TITLE%" "%PYTHON_EXE%" "%SCRIPT_PATH%" "%SCRIPT_ARGS%" "%DEPLOYED_FILE%" "%LOG_FILE%" "%PID_FILE%"

set "EXITCODE=%ERRORLEVEL%"
popd
exit /b %EXITCODE%


REM ==============================================================================
REM  SECOND MODE: actual update steps, runs from STATE_DIR copy
REM ==============================================================================
:RUN_UPDATE_MODE
if /i "%~1" NEQ "run-update" goto :EOF

set "U_REPO_DIR=%~2"
set "U_BRANCH=%~3"
set "U_REMOTE_HASH=%~4"
set "U_WINDOW_TITLE=%~5"
set "U_PYTHON_EXE=%~6"
set "U_SCRIPT_PATH=%~7"
set "U_SCRIPT_ARGS=%~8"
set "U_DEPLOYED_FILE=%~9"
shift & shift & shift & shift & shift & shift & shift & shift & shift
set "U_LOG_FILE=%~1"
set "U_PID_FILE=%~2"

set "U_VENV_DIR=%U_REPO_DIR%\venv"
if "%U_LOG_FILE%"=="" set "U_LOG_FILE=C:\ProgramData\MeerbyPCScript\logs\deploy.log"

echo [%DATE% %TIME%] run-update begin >> "%U_LOG_FILE%"
echo repo="%U_REPO_DIR%" branch="%U_BRANCH%" target=%U_REMOTE_HASH% >> "%U_LOG_FILE%"

pushd "%U_REPO_DIR%" || (echo FATAL: cannot cd to repo >> "%U_LOG_FILE%" & exit /b 1)

echo Performing hard reset... >> "%U_LOG_FILE%"
git reset --hard origin/%U_BRANCH% --quiet
if errorlevel 1 (echo git reset failed >> "%U_LOG_FILE%" & popd & exit /b 1)

REM Stop existing app (only python.exe owned by current user)
if exist "%U_PID_FILE%" (
    set /p APP_PID=<"%U_PID_FILE%"
    if defined APP_PID (
        for /f "tokens=1,2 delims=," %%A in ('tasklist /FI "PID eq !APP_PID!" /FO CSV /NH') do (
            set "PROC_NAME=%%~A"
            set "PROC_USER=%%~B"
        )
        if /i "!PROC_NAME!"=="python.exe" (
            if /i "!PROC_USER!"=="%USERNAME%" (
                echo Killing app PID !APP_PID! >> "%U_LOG_FILE%"
                taskkill /PID !APP_PID! /T >> "%U_LOG_FILE%" 2>&1
            ) else (
                echo PID !APP_PID! belongs to !PROC_USER! — skipping kill. >> "%U_LOG_FILE%"
            )
        ) else (
            echo PID !APP_PID! is not python.exe — skipping kill. >> "%U_LOG_FILE%"
        )
    )
)
timeout /t 1 >nul 2>&1

REM Verify reset
for /f "usebackq" %%h in (`git rev-parse HEAD`) do set "POST_RESET_HASH=%%h"
echo Post-reset HEAD=%POST_RESET_HASH% >> "%U_LOG_FILE%"
if /i not "%POST_RESET_HASH%"=="%U_REMOTE_HASH%" (
    echo WARNING: HEAD mismatch expected=%U_REMOTE_HASH% got=%POST_RESET_HASH% >> "%U_LOG_FILE%"
)

call :ENSURE_AND_START_APP

> "%U_DEPLOYED_FILE%" echo %U_REMOTE_HASH%
echo Deployed %U_REMOTE_HASH% >> "%U_LOG_FILE%"
echo [%DATE% %TIME%] run-update end SUCCESS >> "%U_LOG_FILE%"
popd
exit /b 0


REM ==============================================================================
REM  ENSURE_AND_START_APP
REM  Creates venv, installs requirements.txt, launches Socket_PC1.py.
REM  No secrets injected as env vars — Python reads secrets.bin directly.
REM ==============================================================================
:ENSURE_AND_START_APP
set "L_LOG_FILE=%U_LOG_FILE%"
if not defined L_LOG_FILE set "L_LOG_FILE=%LOG_FILE%"
set "L_VENV_DIR=%U_VENV_DIR%"
if not defined L_VENV_DIR set "L_VENV_DIR=%VENV_DIR%"
set "L_SCRIPT_PATH=%U_SCRIPT_PATH%"
if not defined L_SCRIPT_PATH set "L_SCRIPT_PATH=%SCRIPT_PATH%"
set "L_SCRIPT_ARGS=%U_SCRIPT_ARGS%"
if not defined L_SCRIPT_ARGS set "L_SCRIPT_ARGS=%SCRIPT_ARGS%"
set "L_PID_FILE=%U_PID_FILE%"
if not defined L_PID_FILE set "L_PID_FILE=%PID_FILE%"
set "L_REPO_DIR=%U_REPO_DIR%"
if not defined L_REPO_DIR set "L_REPO_DIR=%REPO_DIR%"
set "L_REQUIREMENTS=%L_REPO_DIR%\requirements.txt"
set "L_BASE_PYTHON=%U_PYTHON_EXE%"
if not defined L_BASE_PYTHON set "L_BASE_PYTHON=%PYTHON_EXE%"
set "L_VENV_PY=%L_VENV_DIR%\Scripts\python.exe"

echo Ensuring venv at %L_VENV_DIR% >> "%L_LOG_FILE%"
if not exist "%L_VENV_PY%" (
    "%L_BASE_PYTHON%" -m venv "%L_VENV_DIR%" >> "%L_LOG_FILE%" 2>&1
)
if exist "%L_VENV_PY%" (
    "%L_VENV_PY%" -m pip install --upgrade pip >> "%L_LOG_FILE%" 2>&1
    if exist "%L_REQUIREMENTS%" (
        "%L_VENV_PY%" -m pip install -r "%L_REQUIREMENTS%" --no-cache-dir >> "%L_LOG_FILE%" 2>&1
    )
)

REM Launch app — no env var secrets injected
echo Starting app (secrets from secrets.bin only)... >> "%L_LOG_FILE%"
set "POWERSHELL_CMD=powershell -NoProfile -Command "$p = Start-Process -FilePath '\"%L_VENV_PY%\"' -ArgumentList '\"%L_SCRIPT_PATH%\" %L_SCRIPT_ARGS%' -PassThru; echo $p.Id""

for /f %%i in ('%POWERSHELL_CMD%') do set "APP_PID=%%i"

if defined APP_PID (
    echo %APP_PID% > "%L_PID_FILE%"
    echo App started PID=%APP_PID% >> "%L_LOG_FILE%"
) else (
    echo Failed to start app. >> "%L_LOG_FILE%"
)

timeout /t 2 >nul 2>&1

if exist "%L_PID_FILE%" (
    set /p APP_PID=<"%L_PID_FILE%"
    tasklist /nh /fi "PID eq !APP_PID!" | findstr /r ".*" >nul && (
        echo App confirmed running. >> "%L_LOG_FILE%"
    ) || (
        echo WARNING: App PID !APP_PID! not detected after start. >> "%L_LOG_FILE%"
    )
) else (
    echo WARNING: PID file not created. >> "%L_LOG_FILE%"
)
goto :EOF