@echo off
title AI Studio Proxy (debug)
cd /d "%~dp0"

set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

echo ============================================================
echo   AI Studio Proxy - debug mode
echo ------------------------------------------------------------
echo   API     : http://127.0.0.1:2048/v1
echo   Auth    : auth_profiles/saved/main.json  (no login needed)
echo   Browser : camoufox visible mode
echo   Stop    : just close this window
echo ------------------------------------------------------------
echo   Cleaning leftover port 3120 before start...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":3120" ^| findstr "LISTENING"') do (
    echo   kill PID %%a
    taskkill /F /T /PID %%a >nul 2>&1
)
echo ============================================================
echo.

.venv\Scripts\python.exe launch_camoufox.py --debug --active-auth-json auth_profiles\saved\main.json

echo.
echo ============================================================
echo   Service exited. Close browser windows manually if any.
echo ============================================================
pause
