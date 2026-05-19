@echo off
REM Double-click this to run install_patch.ps1 with PowerShell
REM (Avoids the "double-click opens in Notepad" problem on .ps1 files)

setlocal
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_patch.ps1" %*

echo.
echo Press any key to close...
pause >nul
