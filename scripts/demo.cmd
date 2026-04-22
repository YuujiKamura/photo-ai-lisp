@echo off
setlocal

REM Find sbcl in this order: %SBCL% -> PATH -> common install paths.
REM Override by setting SBCL env var before running.

if defined SBCL goto :find_browser

where sbcl >nul 2>nul
if %ERRORLEVEL% equ 0 (
  set "SBCL=sbcl"
  goto :find_browser
)

if exist "%ProgramFiles%\Steel Bank Common Lisp\sbcl.exe" (
  set "SBCL=%ProgramFiles%\Steel Bank Common Lisp\sbcl.exe"
  goto :find_browser
)
if exist "%USERPROFILE%\SBCLLocal\PFiles\Steel Bank Common Lisp\sbcl.exe" (
  set "SBCL=%USERPROFILE%\SBCLLocal\PFiles\Steel Bank Common Lisp\sbcl.exe"
  goto :find_browser
)
if exist "%LOCALAPPDATA%\Programs\Steel Bank Common Lisp\sbcl.exe" (
  set "SBCL=%LOCALAPPDATA%\Programs\Steel Bank Common Lisp\sbcl.exe"
  goto :find_browser
)
if exist "C:\sbcl\sbcl.exe" (
  set "SBCL=C:\sbcl\sbcl.exe"
  goto :find_browser
)

echo ERROR: sbcl not found. 1>&2
echo   Install SBCL from https://www.sbcl.org/platform-table.html 1>&2
echo   Then add it to PATH, or run with SBCL env var: 1>&2
echo     set SBCL=C:\path\to\sbcl.exe ^&^& scripts\demo.cmd 1>&2
exit /b 1

:find_browser
REM Pick a browser capable of --app mode. Chrome first, then Edge.
REM Override via BROWSER env var. Skip if NO_APP_WINDOW=1.
if "%NO_APP_WINDOW%"=="1" goto :run
if defined BROWSER goto :spawn_app

if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" (
  set "BROWSER=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
  goto :spawn_app
)
if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" (
  set "BROWSER=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
  goto :spawn_app
)
if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" (
  set "BROWSER=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
  goto :spawn_app
)
if exist "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" (
  set "BROWSER=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
  goto :spawn_app
)
goto :run

:spawn_app
REM Fire-and-forget helper: waits for :8090, then opens the app window.
start "" /b cmd /c "%~dp0_open-app-window.cmd" "%BROWSER%"

:run
"%SBCL%" --load "%~dp0demo.lisp"
