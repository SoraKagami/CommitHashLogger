@echo off
setlocal
rem Runs CommitHashLogger.ps1 with a config file.
rem %~dp0 is the folder this .bat is in; replace it with a full path if the files live elsewhere.
rem Add -Force after "%ConfigFile%" on the powershell line to skip the wrong-repo safety check.

set "ScriptLocation=%~dp0CommitHashLogger.ps1"
set "ConfigFile=%~dp0Example.psd1"

rem Take just the file name (name + extension) out of the ConfigFile path, for messages.
for %%F in ("%ConfigFile%") do set "ConfigName=%%~nxF"

powershell -NoProfile -ExecutionPolicy Bypass -File "%ScriptLocation%" "%ConfigFile%"
if errorlevel 1 echo. & echo *** CommitHashLogger reported an error for %ConfigName% ***

echo.
pause
