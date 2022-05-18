@echo off
set PATH=%PATH%;./lib
taskkill /f /fi "windowtitle eq hive_test*"

start "hive_test "%~dp0    ./hive.exe ./conf/qtest.conf    --index=1
exit
