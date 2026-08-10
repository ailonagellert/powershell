@echo off
:: Double-click launcher for Invoke-BlueScreenRCA.ps1
:: Prefer elevated PowerShell so dump/event collection is complete.
set "SCRIPT=%~dp0Invoke-BlueScreenRCA.ps1"

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting Administrator privileges...
  powershell -NoProfile -Command "Start-Process -FilePath '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%SCRIPT%"" -OpenReport'"
  exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -OpenReport
echo.
pause
