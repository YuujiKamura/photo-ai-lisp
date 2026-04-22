@echo off
REM Internal helper: wait for the hub to accept on :8090, then open
REM the app window. Called in the background by demo.cmd. Not for
REM direct use.
setlocal
set "BROWSER=%~1"
if "%BROWSER%"=="" exit /b 1

set /a _tries=0
:wait
powershell -NoProfile -Command "exit (Test-NetConnection -ComputerName localhost -Port 8090 -InformationLevel Quiet -WarningAction SilentlyContinue) -eq $true | %%{ if ($_) { 0 } else { 1 } }" >nul 2>nul
if %ERRORLEVEL% equ 0 goto :open
set /a _tries+=1
if %_tries% GEQ 40 exit /b 1
timeout /t 1 /nobreak >nul
goto :wait

:open
start "" "%BROWSER%" --app=http://localhost:8090/ --window-size=1280,780
