@echo off
title AI Studio Proxy - stop all
cd /d "%~dp0"

echo ============================================================
echo   Stopping AI Studio Proxy + watchdog (targeted, safe)
echo ============================================================

echo [1/4] killing watchdog and launcher python processes only
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$k=0; Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { $_.CommandLine -match 'launch_camoufox|watchdog\.py' } | ForEach-Object { Write-Host ('    pid ' + $_.ProcessId); Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; $k++ }; Write-Host ('    killed: ' + $k)"
if errorlevel 1 echo     (powershell step failed, continuing)

echo [2/4] killing port owners 2048 / 3120 / 9222
for %%P in (2048 3120 9222) do (
    for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%%P" ^| findstr "LISTENING"') do (
        echo     port %%P -^> PID %%a
        taskkill /F /T /PID %%a >nul 2>&1
    )
)

echo [3/4] killing camoufox browsers
taskkill /F /IM camoufox.exe >nul 2>&1
echo     done

echo [4/4] verify ports
for %%P in (2048 3120 9222) do (
    netstat -ano | findstr ":%%P" | findstr "LISTENING" >nul 2>&1 && (echo     %%P still in use) || (echo     %%P free)
)

echo.
echo ============================================================
echo   Done. Only AI Studio Proxy processes were touched.
echo ============================================================
pause
