@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
cd /d "%~dp0"
title ProgramScraper - installed programs report

rem --- Request administrator privileges (needed to mount NTUSER.DAT of all users) ---
net session >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator privileges...
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    if errorlevel 1 (
        echo [ERROR] Could not elevate privileges.
        pause
    )
    exit /b
)

echo.
echo ============================================================
echo  Collecting installed programs information (Windows 10/11)
echo  Running as administrator
echo ============================================================
echo.

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-InstalledPrograms.ps1" -OutputDir "%~dp0Reports"
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" (
    echo [ERROR] Script finished with code %RC%.
    echo.
    pause
    exit /b %RC%
)

echo Done. Looking for the newest report...
set "LAST="
for /f "delims=" %%F in ('dir /b /od /a-d "%~dp0Reports\*.xlsx" 2^>nul') do set "LAST=%%F"

if defined LAST (
    echo Open: %~dp0Reports\%LAST%
    start "" "%~dp0Reports\%LAST%"
) else (
    echo [WARNING] XLSX file was not found in Reports folder.
)

echo.
pause
exit /b 0
