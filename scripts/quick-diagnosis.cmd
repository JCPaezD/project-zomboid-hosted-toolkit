@echo off
pushd "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\pz-toolkit.ps1" quick-diagnosis %*
set EXITCODE=%ERRORLEVEL%
popd
pause
exit /b %EXITCODE%
