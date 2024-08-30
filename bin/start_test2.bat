@echo off
set PATH=%PATH%;./lib
taskkill /f /fi "windowtitle eq hive_test*"

hive.exe ./conf/qtest.conf    --index=2
exit
