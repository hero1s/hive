#!/bin/sh

if [ ! -d "../bin/proto/" ];then
	mkdir ../bin/proto
fi

chmod 755 protoc
./protoc --descriptor_set_out=../bin/proto/ncmd_cs.pb --proto_path=../proto/ *.proto

echo "build pb file success"
