@echo off
setlocal
cd /d "%~dp0\.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\pz-inspect-auto-backups.ps1" -Details %*
echo.
pause
