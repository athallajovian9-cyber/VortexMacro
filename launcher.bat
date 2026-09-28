@echo off
setlocal EnableExtensions
title Vortex Macro - Prospecting
color 0B
cls

:: ---------------------------------------------------------------
::  Vortex Macro launcher (portable, no installer required)
::  F1 = start   F2 = pause/stop   F7 = record route   F8 = play once   Tray = quit
::
::  System tools are called by absolute path on purpose: a shell
::  such as Git Bash on PATH ships its own find.exe, which shadows
::  the Windows one and silently breaks process detection.
:: ---------------------------------------------------------------

set "SYS=%SystemRoot%\System32"
set "PS=%SYS%\WindowsPowerShell\v1.0\powershell.exe"
set "ROOT=%~dp0"
set "ENGINE=%ROOT%submacro\AutoHotkey.exe"
set "SCRIPT=%ROOT%submacro\VortexMacro.ahk"
set "PLACEID=129827112113663"

echo ===========================================
echo      VORTEX MACRO - PROSPECTING
echo ===========================================
echo.

:: --- 1. verify portable engine -------------------------------
if not exist "%ENGINE%" (
    echo [X] Macro engine not found:
    echo     "%ENGINE%"
    echo.
    echo     Expected AutoHotkey v2 in the submacro folder.
    echo.
    pause
    exit /b 1
)

:: --- 2. verify macro script ----------------------------------
if not exist "%SCRIPT%" (
    echo [X] Macro script not found:
    echo     "%SCRIPT%"
    echo.
    pause
    exit /b 1
)

:: --- 3. stop any previous instance of THIS script ------------
:: Killing by image name would take out unrelated AutoHotkey scripts, so match
:: the command line instead. AHK's own #SingleInstance Force asks the old
:: instance to close itself, which fails while it is busy inside the macro
:: loop -- the new instance then blocks on a "keep waiting?" dialog. Force the
:: kill here and CONFIRM the process is gone before starting a replacement,
:: because a dying instance races the new one and produces the same dialog.
echo [+] Clearing any previous instance...
call :killold
if not errorlevel 1 goto NOSTALE
echo.
echo [X] A previous macro instance would not close.
echo     Right-click its tray icon, choose Exit, then run this again.
echo.
pause
exit /b 1

:NOSTALE

:: --- 4. start the macro engine -------------------------------
echo [+] Starting macro engine...
start "" "%ENGINE%" "%SCRIPT%"

:: --- 5. confirm it actually came up (no silent failure) ------
call :waitfor 3
"%SYS%\tasklist.exe" /FI "IMAGENAME eq AutoHotkey64.exe" /NH 2>nul | "%SYS%\findstr.exe" /I /C:"AutoHotkey64.exe" >nul
if errorlevel 1 (
    echo.
    echo [X] Macro engine did NOT stay running.
    echo     Double-click this file directly rather than using a shortcut.
    echo.
    pause
    exit /b 1
)
echo     Macro engine is running.

:: --- 6. launch the game via a proper deep link ---------------
echo [+] Launching Prospecting...
start "" "roblox://placeId=%PLACEID%"

echo.
echo ===========================================
echo   READY
echo.
echo   F1   = start the macro
echo   F2   = pause / stop the macro
echo   F3   = live pixel readout (vision)
echo   F4   = mark next watch point
echo   F5   = vision status / self-test
echo   F6   = clear watch points
echo   F7   = record a route (press, play the loop by hand, press again)
echo   F8   = replay the recorded route once, to check it
echo   Tray = right-click the green H to exit
echo ===========================================
echo.
echo   Roblox is opening in a separate window.
echo.
pause
endlocal
exit /b 0

:: ---------------------------------------------------------------
::  :waitfor ^<seconds^>
::  Countdown that works even when stdin is redirected, where
::  Windows timeout.exe refuses to run. Uses ping, not sleep.
:: ---------------------------------------------------------------
:waitfor
set /a "_wf=%~1"
:waitfor_loop
if %_wf% LEQ 0 goto :eof
"%SYS%\ping.exe" -n 2 127.0.0.1 >nul 2>&1
set /a "_wf-=1"
goto :waitfor_loop

:: ---------------------------------------------------------------
::  :killold
::  Force-stop every AutoHotkey process running THIS script, then
::  verify. Returns errorlevel 0 when clear, 1 when one survived.
::
::  The process NAME guard is essential: PowerShell's own command
::  line contains the script path, so an unguarded match kills the
::  query process itself and yields an opaque errorlevel -1.
:: ---------------------------------------------------------------
:killold
"%PS%" -NoProfile -NonInteractive -Command "$m = Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'AutoHotkey*' -and $_.CommandLine -like '*VortexMacro.ahk*' }; if ($m) { $m | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Start-Sleep -Seconds 1 }; $q = Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'AutoHotkey*' -and $_.CommandLine -like '*VortexMacro.ahk*' }; if ($q) { 'STUCK' } else { 'GONE' }" 2>nul | "%SYS%\findstr.exe" /C:"GONE" >nul
goto :eof
