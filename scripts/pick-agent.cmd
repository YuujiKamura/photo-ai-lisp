@echo off
@chcp 65001 >nul
setlocal
echo ==============================
echo  photo-ai-lisp : pick an agent
echo ==============================
echo   [1] claude
echo   [2] gemini
echo   [3] codex
echo   [Enter] skip (stay in cmd)
echo ==============================
set /p CHOICE="> "
if "%CHOICE%"=="1" (claude)
if "%CHOICE%"=="2" (gemini)
if "%CHOICE%"=="3" (codex)
