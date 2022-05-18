@echo off
set PATH=%PATH%;..\bin\lib
..\bin\hive.exe ..\tools\excel2lua\excel2lua.conf --input=. --output=../server/config

move ..\server\config\database_cfg.lua ..\bin\svrconf\template
move ..\server\config\router_cfg.lua ..\bin\svrconf\template
move ..\server\config\service_cfg.lua ..\bin\svrconf\template
rd .\logs /s /q
pause

