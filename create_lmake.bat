set PATH=%PATH%;.\bin\lib
set LUA_PATH=!/../tools/lmake/?.lua;!/../script/?.lua;;
bin\hive.exe --entry=lmake

pause