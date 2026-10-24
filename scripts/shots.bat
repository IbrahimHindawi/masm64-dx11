@echo off
:: Renders every built lesson with --shot into shots\<name>.png, or only those whose names contain
:: the first argument. 1.1 and 2.1 write their window out by hand and take no --shot, so they are
:: left out.
setlocal enabledelayedexpansion
set root=%~dp0..
set filter=%~1
if not exist "%root%\shots" mkdir "%root%\shots"
for %%f in ("%root%\build\*.exe") do (
    set run=1
    if /i "%%~nf"=="hello_window" set run=0
    if /i "%%~nf"=="hello_triangle" set run=0
    if not "%filter%"=="" (
        echo %%~nf | findstr /i /c:"%filter%" >nul || set run=0
    )
    if !run!==1 (
        echo %%~nf
        "%%f" --shot "%root%\shots\%%~nf.png"
    )
)
