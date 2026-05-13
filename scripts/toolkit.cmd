@echo off
pushd "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\pz-toolkit.ps1" %*
set EXITCODE=%ERRORLEVEL%
popd
if not "%EXITCODE%"=="0" pause
exit /b %EXITCODE%
