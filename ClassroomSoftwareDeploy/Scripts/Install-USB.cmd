@echo off
setlocal
set "ROOT=%~dp0.."
net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo Requesting administrator rights...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c ""%~f0""' -Verb RunAs"
  exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\Scripts\Install-Local.ps1" -Root "%ROOT%"
echo.
echo Installation finished. See Logs folder.
pause
