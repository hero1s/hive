@echo off
set PATH=%PATH%;..\bin\lib
set LUA_CPATH=!/lib/?.dll;;
set LUA_PATH=!/../tools/excel2lua/?.lua;!/../script/?.lua;;

..\bin\hive.exe --entry=main_convertor --input=. --output=../server/config

move ..\server\config\database_cfg.lua ..\bin\svrconf\template
move ..\server\config\router_cfg.lua ..\bin\svrconf\template
move ..\server\config\service_cfg.lua ..\bin\svrconf\template
rd .\logs /s /q
pause

