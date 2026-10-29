@echo off
title AI Studio Proxy - watchdog
cd /d "%~dp0"

set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

echo ============================================================
echo   AI Studio Proxy - WATCHDOG mode
echo ------------------------------------------------------------
echo   API      : http://127.0.0.1:2048/v1
echo   Auth     : auth_profiles/saved/main.json  (no login needed)
echo   Behavior : polls /health every 20s, auto-restarts when the
echo              page / browser / worker dies (3 fails in a row)
echo   Logs     : logs\watchdog.log  and  logs\watchdog_service.log
echo   Stop     : close this window (service keeps running once
echo              started - kill it manually or use the stop bat)
echo ============================================================
echo.

.venv\Scripts\python.exe watchdog.py

echo.
echo ============================================================
echo   Watchdog exited.
echo ============================================================
pause
