bash ./stop.sh all
bash ./clear_log.sh 1

set -xe
#添加动态库搜索路径
export LD_LIBRARY_PATH=./lib:$LD_LIBRARY_PATH
#设置本机的ip地址(监听及连接访问)
hostip=$1
if [ -z "$hostip" ];then
    hostip=$(ip addr | grep eth0 | awk '/^[0-9]+: / {}; /inet.*global/ {print gensub(/(.*)\/(.*)/, "\\1", "g", $2)}')
    echo "start ip:" ${hostip}
fi
#测试启动服务集群
./hive ./conf/router.conf      --index=1  --host_ip=127.0.0.1

./hive ./conf/monitor.conf     --index=1  --host_ip=%hostIp%
./hive ./conf/dbsvr.conf       --index=1
./hive ./conf/cachesvr.conf    --index=1
./hive ./conf/admin.conf       --index=1