@echo off
setlocal
set "ROOT=%~dp0.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\Scripts\Prepare-OfflineMedia.ps1" -Root "%ROOT%" %*
echo.
echo See Config\OFFLINE-DOWNLOAD-RESULTS.csv and Config\MANUAL-DOWNLOADS.csv
pause
