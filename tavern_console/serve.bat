@echo off
REM  Launcher for serve.ps1 — asks for administrator so it can open the
REM  firewall port, which is the thing that most often makes the phone
REM  time out on an otherwise working server.
REM
REM  Double-click this. Say yes to the admin prompt.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File','%~dp0serve.ps1'"

REM If the admin prompt is refused, fall back to running without it — the
REM server still works, you just have to allow the firewall by hand.
if errorlevel 1 (
  echo.
  echo   Running without administrator. If the phone times out, the
  echo   firewall is the reason - re-run and accept the prompt.
  echo.
  powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0serve.ps1"
)
