@echo off
pushd "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\tools\pz-clear-client-mods.ps1" -WhatIf
popd
pause
