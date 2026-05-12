@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync-obsidian.ps1"
set "EXITCODE=%ERRORLEVEL%"
if %EXITCODE% neq 0 (
  echo.
  echo Sync exited with code %EXITCODE%.
  pause
)
endlocal & exit /b %EXITCODE%
