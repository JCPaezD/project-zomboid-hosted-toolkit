@echo off
pushd "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\tools\pz-audit.ps1"
popd
pause
