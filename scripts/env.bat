@echo off
:: Puts ml64, link and rc on PATH, unless this is already a VS developer prompt.
where ml64.exe >nul 2>&1 && goto :eof
set "vswhere=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq delims=" %%i in (`"%vswhere%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "vsdir=%%i"
if not defined vsdir (
    echo error: no Visual Studio with the C++ x64 tools was found
    exit /b 1
)
call "%vsdir%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
