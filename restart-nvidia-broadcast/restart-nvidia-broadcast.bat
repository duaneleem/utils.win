@echo off
setlocal

set "EXE=C:\Program Files\NVIDIA Corporation\NVIDIA Broadcast\NVIDIA Broadcast.exe"

echo Stopping NVIDIA Broadcast...
taskkill /IM "NVIDIA Broadcast.exe" /F >nul 2>&1
if %errorlevel% equ 0 (
    echo Process stopped. Waiting 2 seconds...
    timeout /t 2 /nobreak >nul
) else (
    echo No running process found (or already closed).
)

echo Starting NVIDIA Broadcast...
start "" "%EXE%"
echo Done.

endlocal
