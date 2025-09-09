@echo off
setlocal enabledelayedexpansion

if /i "%~1"=="run-update" goto RUN_UPDATE_MODE

REM ==============================================================================
REM  Meerby: Auto-update & restart (single script, safe to live inside the repo)
REM  Repo: https://github.com/ZodiacGroupToronto/Meerby-Solt-Reciever-Beacons.git
REM  Branch: release
REM
REM  WHAT THIS DOES:
REM    1) git fetch origin release
REM    2) Compare local HEAD vs origin/release
REM    3) If no change -> exit quietly
REM    4) If changed   -> copy THIS script to %TEMP% and run the temp copy to:
REM           - git reset --hard origin/release
REM           - stop your running app (scoped kill by window title)
REM           - start your app again
REM           - record the deployed commit hash
REM
REM  WHY SELF-COPY?
REM    Because this file lives in the repo and a hard reset can overwrite it.
REM    Running the update steps from a temp copy avoids file-in-use issues.
REM ==============================================================================

REM -----------------------------
REM CONFIG — EDIT ME
REM -----------------------------
set "REPO_DIR=%USERPROFILE%\Meerby-Solt-Reciever-Beacons"
set "BRANCH=release"

REM Where to store state/logs OUTSIDE the repo so they survive resets
set "STATE_DIR=%USERPROFILE%\Desktop\MeerbyUpdater"
set "DEPLOYED_FILE=%STATE_DIR%\last_deployed_commit.txt"
set "LOG_FILE=%STATE_DIR%\deploy.log"

REM Your app process settings (adjust to your environment)
set "WINDOW_TITLE=MeerbySoltReceiver"
set "PYTHON_EXE=%USERPROFILE%\AppData\Local\Programs\Python\Python311\python.exe"
set "SCRIPT_PATH=%REPO_DIR%\Socket_PC1.py"

REM OPTIONAL: extra args to your script
set "SCRIPT_ARGS="

REM Git remote (public)
set "REMOTE_URL=https://github.com/ZodiacGroupToronto/Meerby-Solt-Reciever-Beacons.git"

REM -----------------------------
REM INIT: ensure state dir exists & log header
REM -----------------------------
if not exist "%STATE_DIR%" mkdir "%STATE_DIR%" >nul 2>&1
echo [%DATE% %TIME%] --- updater start --- >> "%LOG_FILE%"

REM -----------------------------
REM PRECHECK: we must be inside the repo folder to run
REM -----------------------------
if not exist "%REPO_DIR%\.git" (
  echo Repo folder or .git not found at "%REPO_DIR%". >> "%LOG_FILE%"
  echo Please clone the repo first:
  echo   git clone "%REMOTE_URL%" "%REPO_DIR%"
  exit /b 1
)

pushd "%REPO_DIR%" || (echo Failed to cd to repo >> "%LOG_FILE%" & exit /b 1)

REM -----------------------------
REM STEP 1: fetch the remote branch data (no changes to working tree yet)
REM -----------------------------
git fetch origin %BRANCH% --quiet
if errorlevel 1 (
  echo git fetch failed >> "%LOG_FILE%"
  popd
  exit /b 1
)

REM -----------------------------
REM STEP 2: get local HEAD and remote tip commit hashes
REM -----------------------------
for /f "usebackq" %%h in (`git rev-parse HEAD`) do set "LOCAL_HASH=%%h"
for /f "usebackq" %%h in (`git rev-parse origin/%BRANCH%`) do set "REMOTE_HASH=%%h"

if "%LOCAL_HASH%"=="" (
  echo Failed to get LOCAL_HASH >> "%LOG_FILE%"
  popd
  exit /b 1
)
if "%REMOTE_HASH%"=="" (
  echo Failed to get REMOTE_HASH >> "%LOG_FILE%"
  popd
  exit /b 1
)

REM -----------------------------
REM STEP 3: if no change, exit quietly
REM -----------------------------
if "%LOCAL_HASH%"=="%REMOTE_HASH%" (
  echo No change. local=%LOCAL_HASH% >> "%LOG_FILE%"
  @REM popd
  @REM exit /b 0
)

echo Change detected: %LOCAL_HASH% -> %REMOTE_HASH% >> "%LOG_FILE%"

REM -----------------------------
REM STEP 4: SELF-COPY to TEMP and run the updater from there
REM          (avoids hard reset clobbering the running script)
REM -----------------------------
set "TEMP_RUN=%STATE_DIR%\meerby_update_runner.bat"
copy /Y "%~f0" "%TEMP_RUN%" >nul
if errorlevel 1 (
  echo Failed to copy self to temp "%TEMP_RUN%" >> "%LOG_FILE%"
  popd
  exit /b 1
)

REM Pass args needed by the runner:
REM   %1 = action flag ("run-update")
REM   %2 = REPO_DIR
REM   %3 = BRANCH
REM   %4 = REMOTE_HASH
REM   %5 = WINDOW_TITLE
REM   %6 = PYTHON_EXE
REM   %7 = SCRIPT_PATH
REM   %8 = SCRIPT_ARGS
REM   %9 = DEPLOYED_FILE
REM   %10 = LOG_FILE
call "%TEMP_RUN%" run-update "%REPO_DIR%" "%BRANCH%" "%REMOTE_HASH%" "%WINDOW_TITLE%" "%PYTHON_EXE%" "%SCRIPT_PATH%" "%SCRIPT_ARGS%" "%DEPLOYED_FILE%" "%LOG_FILE%"

set "EXITCODE=%ERRORLEVEL%"
popd
exit /b %EXITCODE%


REM ==============================================================================
REM SECOND MODE: the same file, when invoked with "run-update", performs the
REM              actual hard reset + app restart from %TEMP% (safe context).
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

if "%U_LOG_FILE%"=="" (
  set "U_LOG_FILE=%USERPROFILE%\Desktop\MeerbyUpdater\deploy.log"
)

echo [%DATE% %TIME%] run-update begin >> "%U_LOG_FILE%"
echo Running update with: repo="%U_REPO_DIR%" branch="%U_BRANCH%" targetCommit=%U_REMOTE_HASH% >> "%U_LOG_FILE%"

if not exist "%U_REPO_DIR%" echo ERROR: Repo dir missing "%U_REPO_DIR%" >> "%U_LOG_FILE%"
if not exist "%U_REPO_DIR%\.git" echo ERROR: .git missing in repo dir "%U_REPO_DIR%" >> "%U_LOG_FILE%"

REM --- Change to the repo 
pushd "%U_REPO_DIR%"
echo pushd.errorlevel=%ERRORLEVEL% after attempting pushd >> "%U_LOG_FILE%"
if errorlevel 1 (
  echo pushd reported failure. Trying fallback cd /d. >> "%U_LOG_FILE%"
  cd /d "%U_REPO_DIR%" 2>>"%U_LOG_FILE%"
  echo fallback cd.errorlevel=%ERRORLEVEL% >> "%U_LOG_FILE%"
  if errorlevel 1 (
    echo FATAL: Cannot change directory to "%U_REPO_DIR%" >> "%U_LOG_FILE%"
    exit /b 1
  ) else (
    echo Fallback cd succeeded. (Not using directory stack) >> "%U_LOG_FILE%"
  )
) else (
  echo pushd success. Now CWD=%CD% >> "%U_LOG_FILE%"
)

if not exist .git echo WARNING: .git still not found in CWD=%CD% >> "%U_LOG_FILE%"

echo Performing hard reset... >> "%U_LOG_FILE%"
REM --- Do the hard reset now that we’re running from TEMP, not the repo file
git reset --hard origin/%U_BRANCH% --quiet
if errorlevel 1 (
  echo git reset failed >> "%U_LOG_FILE%"
  popd
  exit /b 1
)

echo Reset to %U_REMOTE_HASH% >> "%U_LOG_FILE%"
for /f "usebackq" %%h in (`git rev-parse HEAD`) do set "POST_RESET_HASH=%%h"
echo Post-reset HEAD=%POST_RESET_HASH% >> "%U_LOG_FILE%"
if /i not "%POST_RESET_HASH%"=="%U_REMOTE_HASH%" echo WARNING: HEAD mismatch expected=%U_REMOTE_HASH% got=%POST_RESET_HASH% >> "%U_LOG_FILE%"

echo Stopping existing app (window title match) >> "%U_LOG_FILE%"
REM --- Stop the existing app instance (scoped by unique window title)
taskkill /FI "WINDOWTITLE eq %U_WINDOW_TITLE%" /F >nul 2>&1

REM --- Start the app with the same unique title so we can target it next time
echo Starting app... >> "%U_LOG_FILE%"
if "%U_SCRIPT_ARGS%"=="" (
  echo start "%U_WINDOW_TITLE%" cmd /c ""%U_PYTHON_EXE%" "%U_SCRIPT_PATH%"" >> "%U_LOG_FILE%"
  start "%U_WINDOW_TITLE%" cmd /c ""%U_PYTHON_EXE%" "%U_SCRIPT_PATH%""
) else (
  echo start "%U_WINDOW_TITLE%" cmd /c ""%U_PYTHON_EXE%" "%U_SCRIPT_PATH%" %U_SCRIPT_ARGS%" >> "%U_LOG_FILE%"
  start "%U_WINDOW_TITLE%" cmd /c ""%U_PYTHON_EXE%" "%U_SCRIPT_PATH%" %U_SCRIPT_ARGS%"
)

timeout /t 2 >nul 2>&1
(tasklist /v /fi "WINDOWTITLE eq %U_WINDOW_TITLE%" | find /i "%U_WINDOW_TITLE%" >nul ) && (
  echo App process detected running. >> "%U_LOG_FILE%"
) || (
  echo WARNING: App window not detected after restart. >> "%U_LOG_FILE%"
)

REM --- Record deployed commit hash for reference (optional but handy)
for %%d in ("%U_DEPLOYED_FILE%") do (
  if not exist "%%~dpd" mkdir "%%~dpd" >nul 2>&1
)
> "%U_DEPLOYED_FILE%" echo %U_REMOTE_HASH%

echo Deployed %U_REMOTE_HASH% and restarted. >> "%U_LOG_FILE%"
echo Update success commit=%U_REMOTE_HASH% >> "%U_LOG_FILE%"
echo [%DATE% %TIME%] run-update end SUCCESS >> "%U_LOG_FILE%"
popd
exit /b 0