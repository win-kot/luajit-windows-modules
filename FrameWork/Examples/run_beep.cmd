@echo off
setlocal
pushd "%~dp0"
if errorlevel 1 exit /b 1
luajit "17_system_beep.lua"
set "beep_exit=%errorlevel%"
popd
if not "%beep_exit%"=="0" pause
exit /b %beep_exit%
