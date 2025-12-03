@echo off
setlocal enabledelayedexpansion

REM ===========================================
REM  Meerby: Stop Task Script
REM ===========================================

REM -----------------------------
REM CONFIG — EDIT ME
REM -----------------------------
set "REPO_DIR=%USERPROFILE%\Meerby-Solt-Reciever-Beacons"
set "PID_FILE=%REPO_DIR%\app.pid"

set "STATE_DIR=%USERPROFILE%\Desktop\MeerbyUpdater"
set "LOG_FILE=%STATE_DIR%\deploy.log"

if not exist "%PID_FILE%" (
    echo [%DATE% %TIME%] No PID file found. Is the app running? >> "%LOG_FILE%"
    goto :EOF
) else (
    echo [%DATE% %TIME%] Stopping app with PID from %PID_FILE% >> "%LOG_FILE%"
    set "EXIST_PID="
    set /p EXIST_PID=<"%PID_FILE%"
    if defined EXIST_PID (
        echo [%DATE% %TIME%] Killing PID !EXIST_PID! >> "%LOG_FILE%"
        taskkill /PID !EXIST_PID! /F /T >> "%LOG_FILE%" 2>&1
        if errorlevel 1 (
            echo [%DATE% %TIME%] taskkill failed for PID !EXIST_PID! >> "%LOG_FILE%"
        ) else (
            echo [%DATE% %TIME%] Successfully killed PID !EXIST_PID! >> "%LOG_FILE%"
        )    
    ) else (
        echo [%DATE% %TIME%] No PID read from PID file. >> "%LOG_FILE%"
    )
)
timeout /t 2 >nul 2>&1

goto :EOF
