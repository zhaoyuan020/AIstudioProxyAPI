@echo off
setlocal
title AI Studio Proxy - ADD ACCOUNT
cd /d "%~dp0"

set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

echo ============================================================
echo   ADD A NEW ACCOUNT
echo ------------------------------------------------------------
echo   You will be asked ONCE for a name (here, in cmd).
echo   Then in the browser window: sign OUT of the current
echo   Google account, then sign IN with the new one.
echo   After AI Studio loads, press Enter in this window.
echo ------------------------------------------------------------
echo   Name rule: letters / digits / _ / -  only, no .json
echo   Example  : main3
echo ============================================================
echo.

set "NAME="
set /p "NAME=  Account name: "
if "%NAME%"=="" (
    echo.
    echo   [ERROR] name is required, aborted.
    pause
    exit /b 1
)

if exist "auth_profiles\saved\%NAME%.json" (
    echo.
    echo   [WARN] auth_profiles\saved\%NAME%.json already exists.
    echo          Continuing will OVERWRITE it.
    echo.
    pause
)

echo.
echo   Target file : auth_profiles\saved\%NAME%.json
echo   Launcher prompts are skipped via CLI args.
echo.
echo   Cleaning leftover port 3120 before start...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":3120" ^| findstr "LISTENING"') do (
    taskkill /F /T /PID %%a >nul 2>&1
)
echo ============================================================
echo.

.venv\Scripts\python.exe launch_camoufox.py --debug --auto-save-auth --save-auth-as "%NAME%"

echo.
echo ============================================================
echo   Finished. Look for: auth_profiles\saved\%NAME%.json
echo ============================================================
pause
