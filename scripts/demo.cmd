@echo off
REM Use sbcl from PATH. If not found, install SBCL or add it to PATH
REM (override via SBCL env var if your install lives elsewhere).
if defined SBCL (
  "%SBCL%" --load "%~dp0demo.lisp"
) else (
  sbcl --load "%~dp0demo.lisp"
)
