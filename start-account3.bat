@echo off
title AI Studio Proxy - account 3
cd /d "%~dp0"

set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

echo ============================================================
echo   AI Studio Proxy - ACCOUNT 3  (main3.json)
echo ------------------------------------------------------------
echo   API  : http://127.0.0.1:2048/v1
echo   Auth : auth_profiles\saved\main3.json
echo ------------------------------------------------------------
echo   Cleaning leftover port 3120 before start...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":3120" ^| findstr "LISTENING"') do (
    taskkill /F /T /PID %%a >nul 2>&1
)
echo ============================================================
echo.

if not exist "auth_profiles\saved\main3.json" (
    echo [ERROR] auth_profiles\saved\main3.json not found.
    echo         Run add-account.bat with name "main3" first.
    pause
    exit /b 1
)

.venv\Scripts\python.exe launch_camoufox.py --debug --active-auth-json "auth_profiles\saved\main3.json"

echo.
echo ============================================================
echo   Exited.
echo ============================================================
pause
