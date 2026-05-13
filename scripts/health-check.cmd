@echo off
pushd "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\pz-toolkit.ps1" health-check %*
set EXITCODE=%ERRORLEVEL%
popd
pause
exit /b %EXITCODE%
