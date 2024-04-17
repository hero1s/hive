
@echo off
SETLOCAL EnableDelayedExpansion

if exist .\bin\lib (
    del .\bin\lib\*.dll /f /s /q
    del .\bin\*.exe /f /s /q
    echo "delete old lib"
) else (
    md .\bin\lib
)

if not exist "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" (
  echo "WARNING: You need VS 2019 version or later (for vswhere.exe)"
)

set vswherestr=^"!ProgramFiles(x86)!\Microsoft Visual Studio\Installer\vswhere.exe^" -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
for /f "usebackq tokens=*" %%i in (`!vswherestr!`) do (  
  set BUILDVCTOOLS=%%i\Common7\IDE
  echo BUILDVCTOOLS: !BUILDVCTOOLS!
  if not exist !BUILDVCTOOLS!\devenv.com (
    echo Error: Cannot find VS2019 or later
    exit /b 2
  )
 "!BUILDVCTOOLS!\devenv.com" .\hive.sln /Rebuild
 "!BUILDVCTOOLS!\devenv.com" .\hive.sln /Build
 goto :break
)

:break
move .\bin\*.dll .\bin\lib

pause
