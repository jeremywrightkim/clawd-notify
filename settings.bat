@echo off
setlocal
rem ------------------------------------------------------------
rem  Claude Code - Clawd notification settings
rem  Double-click to open the settings window.
rem ------------------------------------------------------------

set "UI=%USERPROFILE%\.claude\claude-notify-settings.ps1"

if not exist "%UI%" (
    echo.
    echo  [X] Settings UI not found.
    echo      Run install.bat first.
    echo.
    pause
    exit /b 1
)

start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%UI%"
exit /b 0
