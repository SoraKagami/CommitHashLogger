@echo off
rem Runs CommitHashLogger.ps1 with a config file from the same folder as this .bat.
rem Copy the "powershell" line once per config file to update several logs in one go.
rem Add -Force after the config path to skip the wrong-repo safety check.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0CommitHashLogger.ps1" "%~dp0Example.psd1"
if errorlevel 1 echo. & echo *** CommitHashLogger reported an error for Example.psd1 ***

echo.
pause
