@echo off
pushd "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\tools\pz-repair-workshop-redownload.ps1" -WhatIf
popd
pause
