@echo off
setlocal
rem ------------------------------------------------------------
rem  Claude Code - Clawd toast notification installer
rem  Double-click this file to install.
rem ------------------------------------------------------------

set "PS1=%~dp0Install-ClawdNotify.ps1"

if not exist "%PS1%" (
    echo.
    echo  [X] Install-ClawdNotify.ps1 not found.
    echo      It must be in the same folder as this file.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
exit /b %ERRORLEVEL%
