@echo off
setlocal
title AI Studio Proxy - pick account by name
cd /d "%~dp0"

set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

echo ============================================================
echo   AI Studio Proxy - start with a named account
echo ------------------------------------------------------------
echo   Available accounts:
for %%f in ("auth_profiles\saved\*.json") do echo     %%~nf
echo ------------------------------------------------------------
echo   Type the name (without .json), e.g.  main  /  main2
echo ============================================================
echo.

set "NAME="
set /p "NAME=  Account name: "
if "%NAME%"=="" (
    echo   [ERROR] name is required.
    pause
    exit /b 1
)

if not exist "auth_profiles\saved\%NAME%.json" (
    echo.
    echo   [ERROR] auth_profiles\saved\%NAME%.json not found.
    pause
    exit /b 1
)

echo.
echo   Using : auth_profiles\saved\%NAME%.json
echo   API   : http://127.0.0.1:2048/v1
echo.
echo   Cleaning leftover port 3120 before start...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":3120" ^| findstr "LISTENING"') do (
    taskkill /F /T /PID %%a >nul 2>&1
)
echo ============================================================
echo.

.venv\Scripts\python.exe launch_camoufox.py --debug --active-auth-json "auth_profiles\saved\%NAME%.json"

echo.
echo ============================================================
echo   Exited.
echo ============================================================
pause
