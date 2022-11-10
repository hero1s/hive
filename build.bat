@echo off

if exist .\bin\lib (
    del .\bin\lib\*.dll /f /s /q
    del .\bin\*.exe /f /s /q
    echo "delete old lib"
) else (
    md .\bin\lib
)

::C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\Common7\IDE 环境变量
devenv .\hive.sln /Rebuild
devenv .\hive.sln /Build

move .\bin\*.dll .\bin\lib

pause
