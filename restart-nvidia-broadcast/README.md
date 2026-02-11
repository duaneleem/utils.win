# Restart NVIDIA Broadcast

Restarts NVIDIA Broadcast (and optionally OBS) in one shot—handy when Broadcast crashes or gets stuck.

**What it does:**

1. Force-closes **NVIDIA Broadcast** and **OBS** so drivers and processes can release.
2. Waits 4 seconds for cleanup.
3. Starts **NVIDIA Broadcast** again.

OBS is closed so the restart is clean; you can open OBS again yourself after.

**How to run:** Double-click `restart-nvidia-broadcast.bat` or run it from a terminal.

**Different install paths (e.g. another PC):** Copy `.env.sample` to `.env` in this folder and edit the paths. If `.env` is missing, the script uses `%ProgramFiles%` defaults.
