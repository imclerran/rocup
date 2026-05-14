@echo off
rem rocup cmd shim. Forwards all args to rocup.ps1 via Windows PowerShell.
rem %~dp0 resolves to the dir containing this .cmd file. When installed,
rem rocup.cmd lives at $ROCUP_HOME\bin\rocup.cmd, so rocup.ps1 is one dir up.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\rocup.ps1" %*
