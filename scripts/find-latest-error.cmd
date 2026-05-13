@echo off
pushd "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\tools\pz-find-latest-error.ps1" -ServerOnly
popd
pause
