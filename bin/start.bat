@echo off
set PATH=%PATH%;./lib
chcp 65001

call ./stop.bat

set hostIp=%1
if "%hostIp%"=="" (
	for /f "tokens=4" %%a in ('route print^|findstr 0.0.0.0.*0.0.0.0') do (
		set hostIp=%%a
	)
)

if exist "%1" set hostIp=%1

echo "start ip :"%hostIp%

rem 删除旧日志
rd .\logs /s /q
rem 测试启动服务集群
start "router1 "%~dp0       ./hive.exe ./conf/router.conf      --index=1  --host_ip=127.0.0.1
rem start "router2 "%~dp0       ./hive.exe ./conf/router.conf      --index=2  --host_ip=127.0.0.1
start "monitor "%~dp0       ./hive.exe ./conf/monitor.conf     --index=1  --host_ip=%hostIp%
start "dbsvr1 "%~dp0        ./hive.exe ./conf/dbsvr.conf       --index=1
rem start "dbsvr2 "%~dp0        ./hive.exe ./conf/dbsvr.conf       --index=2
start "cachesvr1 "%~dp0     ./hive.exe ./conf/cachesvr.conf    --index=1
rem start "cachesvr2 "%~dp0     ./hive.exe ./conf/cachesvr.conf    --index=2
start "proxy1 "%~dp0        ./hive.exe ./conf/proxy.conf       --index=1
rem start "proxy2 "%~dp0        ./hive.exe ./conf/proxy.conf       --index=2
start "online1 "%~dp0       ./hive.exe ./conf/online.conf      --index=1
rem start "online2 "%~dp0       ./hive.exe ./conf/online.conf      --index=2
start "admin "%~dp0         ./hive.exe ./conf/admin.conf       --index=1

exit
