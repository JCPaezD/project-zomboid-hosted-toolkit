@echo off
setlocal
cd /d "%~dp0\.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\pz-restore-auto-backup.ps1" -WhatIf %*
echo.
pause
