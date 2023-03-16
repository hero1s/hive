@echo off
set PATH=%PATH%;..\bin\lib
set LUA_PATH=!/../tools/excel2lua/?.lua;!/../script/?.lua;;

..\bin\hive.exe --entry=main_convertor --input=. --output=../server/config

rem rd .\logs /s /q
pause

