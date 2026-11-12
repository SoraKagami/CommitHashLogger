@echo off
setlocal
rem Runs CommitHashLogger.ps1 once for each config file listed below.
rem %~dp0 is the folder this .bat is in; replace it with a full path if the files live elsewhere.
rem Add -Force after "%~1" on the powershell line to skip the wrong-repo safety check.

set "ScriptLocation=%~dp0CommitHashLogger.ps1"
set /a Total=0
set /a Failed=0

rem ---- Config files to run: one "call :RunConfig" line per config file ----
call :RunConfig "%~dp0Example.psd1"
rem call :RunConfig "%~dp0AnotherConfig.psd1"
rem call :RunConfig "D:\Some Other Folder\ThirdConfig.psd1"
rem -------------------------------------------------------------------------

echo Finished: %Total% config file(s) run, %Failed% reported an error.
echo.
pause
exit /b %Failed%

rem Runs the script with one config file. %~1 is the config path, %~nx1 is just its file name.
:RunConfig
set /a Total+=1
echo === %~nx1 ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%ScriptLocation%" "%~1"
if errorlevel 1 set /a Failed+=1 & echo. & echo *** CommitHashLogger reported an error for %~nx1 ***
echo.
exit /b 0
