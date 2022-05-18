set -xe
#添加动态库搜索路径
export LD_LIBRARY_PATH=./lib:$LD_LIBRARY_PATH

./hive ./conf/qtest.conf  --index=1

