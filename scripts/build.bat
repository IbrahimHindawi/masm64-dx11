@echo off
:: Builds every lesson, or only those whose file name contains the first argument:
::
::     scripts\build.bat                 all of them
::     scripts\build.bat hello           1.1 hello_window and 2.1 hello_triangle
::
:: Each lesson is one .asm file that includes everything it needs (a unity build), so building it
:: is one ml64 and one link. The programs land in build\, named after their files.
setlocal enabledelayedexpansion
call "%~dp0env.bat" || exit /b 1

set root=%~dp0..
set filter=%~1

:: The MASM64 SDK is not part of this repository: install it from masm32.com into C:\masm64,
:: or point MASM64_HOME at wherever it is.
if not defined MASM64_HOME set MASM64_HOME=C:\masm64
if not exist "%MASM64_HOME%\macros64\macros64.inc" (
    echo The MASM64 SDK is not in %MASM64_HOME%. Install it from https://masm32.com into C:\masm64,
    echo or set MASM64_HOME to the folder that holds include64 and macros64.
    exit /b 1
)
set mlargs=/nologo /c /Cp /Zi /Zd /W2 /I"%root%\includes" /I"%MASM64_HOME%\include64" /I"%MASM64_HOME%\macros64"
set libs=kernel32.lib user32.lib ole32.lib d3d11.lib d3dcompiler.lib
set linkargs=/nologo /debug:full /entry:main /subsystem:console /machine:x64 /opt:ref /opt:noicf %libs%

if not exist "%root%\build\obj" mkdir "%root%\build\obj"
set failed=0
for /r "%root%\src" %%f in (*.asm) do (
    set name=%%~nf
    set build=1
    if not "%filter%"=="" (
        echo %%~nf | findstr /i /c:"%filter%" >nul || set build=0
    )
    if !build!==1 (
        echo %%~nf
        ml64 %mlargs% /Fo"%root%\build\obj\%%~nf.obj" "%%f" > "%root%\build\obj\%%~nf.log"
        if errorlevel 1 (
            type "%root%\build\obj\%%~nf.log"
            set failed=1
        ) else (
            link "%root%\build\obj\%%~nf.obj" %linkargs% /out:"%root%\build\%%~nf.exe" /pdb:"%root%\build\%%~nf.pdb" > "%root%\build\obj\%%~nf.link.log"
            if errorlevel 1 (
                type "%root%\build\obj\%%~nf.link.log"
                set failed=1
            )
        )
    )
)
exit /b !failed!
