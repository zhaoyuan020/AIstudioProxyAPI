@echo off
title AI Studio Proxy - pick account
cd /d "%~dp0"

set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

echo ============================================================
echo   START and PICK an account to use
echo ------------------------------------------------------------
echo   When asked "Create and save new auth file?"  =  n
echo   Then a numbered list of saved profiles appears, e.g.
echo       1) main.json
echo       2) main2.json
echo   Type the number and press Enter (30s timeout).
echo ------------------------------------------------------------
echo   API : http://127.0.0.1:2048/v1
echo ------------------------------------------------------------
echo   Cleaning leftover port 3120 before start...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":3120" ^| findstr "LISTENING"') do (
    taskkill /F /T /PID %%a >nul 2>&1
)
echo ============================================================
echo.

REM No --active-auth-json: launcher lists saved profiles for selection.
.venv\Scripts\python.exe launch_camoufox.py --debug

echo.
echo ============================================================
echo   Exited.
echo ============================================================
pause
