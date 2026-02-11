@echo off
setlocal

REM Load paths from .env only (not .env.sample) if present; else use defaults (%ProgramFiles%)
if exist "%~dp0.env" (
  for /f "usebackq delims=" %%L in ("%~dp0.env") do %%L
) else (
  set "EXE=%ProgramFiles%\NVIDIA Corporation\NVIDIA Broadcast\NVIDIA Broadcast.exe"
  set "OBS=%ProgramFiles%\obs-studio\bin\64bit\obs64.exe"
)

REM Force-close NVIDIA Broadcast and OBS so they can be restarted cleanly
echo Stopping NVIDIA Broadcast and OBS...
taskkill /IM "NVIDIA Broadcast.exe" /F >nul 2>&1
taskkill /IM "obs64.exe" /F >nul 2>&1

REM Give drivers and processes time to release before starting again
echo Waiting 4 seconds for cleanup...
timeout /t 4 /nobreak >nul

REM Launch NVIDIA Broadcast (empty "" is window title so start runs the exe, not a new cmd)
echo Starting NVIDIA Broadcast...
start "" "%EXE%"
echo Done.

endlocal
