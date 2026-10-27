@echo off
setlocal
set "PSModulePath="
rem Stay outside the pack folder: an update replaces it, and Windows cannot
rem rename a folder that this console is using as its working directory.
cd /d "%~dp0.."
title Ultimate AI Starter Bundle v8.25.2
if /I "%~1"=="-?" goto help
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL-AIO.ps1" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" (
  echo [ERROR] Installation failed with exit code %EXITCODE%.
  echo [ERROR] Durable diagnostics were written to:
  echo         "%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\logs\INSTALL-FAILED.txt"
  echo         "%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\logs\INSTALL-LAST.log"
  if /I not "%UABS_NO_PAUSE%"=="1" pause
) else (
  echo [OK] Installation complete.
  echo [OK] Close and reopen your AI apps once. You can close this window.
  if /I not "%UABS_NO_PAUSE%"=="1" pause
)
exit /b %EXITCODE%

:help
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL-AIO.ps1" -?
exit /b %ERRORLEVEL%
