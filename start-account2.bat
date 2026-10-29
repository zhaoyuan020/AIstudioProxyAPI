@echo off
title AI Studio Proxy - account 2
cd /d "%~dp0"

set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

echo ============================================================
echo   AI Studio Proxy - ACCOUNT 2  (main2.json)
echo ------------------------------------------------------------
echo   API  : http://127.0.0.1:2048/v1
echo   Auth : auth_profiles\saved\main2.json
echo ------------------------------------------------------------
echo   No interactive prompt is used on purpose: the launcher's
echo   input_with_timeout() leaves a zombie reader thread behind
echo   after a timeout, which swallows the next typed answer.
echo   Passing --active-auth-json skips those prompts entirely.
echo ------------------------------------------------------------
echo   Cleaning leftover port 3120 before start...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":3120" ^| findstr "LISTENING"') do (
    taskkill /F /T /PID %%a >nul 2>&1
)
echo ============================================================
echo.

if not exist "auth_profiles\saved\main2.json" (
    echo [ERROR] auth_profiles\saved\main2.json not found.
    echo         Run add-account.bat first.
    pause
    exit /b 1
)

.venv\Scripts\python.exe launch_camoufox.py --debug --active-auth-json "auth_profiles\saved\main2.json"

echo.
echo ============================================================
echo   Exited.
echo ============================================================
pause
