@echo off
setlocal enabledelayedexpansion

REM --- Go to User's home directory
cd %USERPROFILE%

REM --- Go to repo directory
cd Meerby-Solt-Reciever-Beacons

REM --- Let User know it will take a few secs
echo Running Solt Script so you can grab Solt Id. Please Wait a few secs....

REM === Ensure Python is available (py first, then python)
set "PY_CMD="
where py >nul 2>nul && set "PY_CMD=py"
if not defined PY_CMD where python >nul 2>nul && set "PY_CMD=python"

if not defined PY_CMD (
    echo ❌ Python was not found in PATH. Please install Python or add it to PATH, then re-run this script.
    goto post_python
)

REM === Install Python dependencies BEFORE running the PC script
if exist requirements.txt (
    echo 📦 Installing dependencies from requirements.txt ...
    call %PY_CMD% -m pip install -r requirements.txt
) else (
    echo ⚠️ requirements.txt not found, skipping dependency install.
)

REM === Run PC script(s) in a different window
echo ▶️ Launching Socket_PC1.py in a new window...
REM Use cmd /k to keep the new window open; use /c if you prefer it to close when done
start "Socket_PC1" cmd /k call %PY_CMD% ".\Socket_PC1.py"

:post_python

REM --- Ask user for Solt Receiver Serial ID
set /p SOLTID=Enter your Solt Receiver Serial ID (Close the window before before proceeding): 

REM --- Add Serial ID to .env
echo SOLT_RECIVER_SERIAL_ID=%SOLTID%>> .env

REM --- CHECKPOINT: Run update again
echo Running solt script again... Look for "INFO - Consumer - Receiver registered"

REM === Run PC script(s) in a different window
echo ▶️ Launching Socker_PC1.py in a new window...
REM Use cmd /k to keep the new window open; use /c if you prefer it to close when done
start "Socket_PC1" cmd /k call %PY_CMD% ".\Socket_PC1.py"

:post_python

echo If you see the line "INFO - Consumer - Receiver registered", all is good

REM --- Ask if user wants to delete log
set /p DELETELOG=Do you want to delete pcLogs.txt from Desktop? (y/n): 
if /i "%DELETELOG%"=="y" (
    if exist "%USERPROFILE%\Desktop\pcLogs.txt" (
        del "%USERPROFILE%\Desktop\pcLogs.txt"
        echo pcLogs.txt deleted successfully.
    ) else (
        echo No pcLogs.txt found on Desktop.
    )
)

REM --- Final confirmation
echo Setup complete! Proceed to Task Scheduler creation steps in Trello.
pause