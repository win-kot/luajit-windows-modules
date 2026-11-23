@echo off
setlocal
pushd "%~dp0"
if errorlevel 1 exit /b 1
if exist "%~dp0..\..\runtime\luajit.exe" (
    "%~dp0..\..\runtime\luajit.exe" "main.lua"
) else (
    luajit "main.lua"
)
set "lesson_exit=%errorlevel%"
popd
if not "%lesson_exit%"=="0" pause
exit /b %lesson_exit%
