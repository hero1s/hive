# hive
Distributed game server framework based on CPP 17 && LUA 5.4

* 框架(hive)+逻辑(server)
* 支持跨平台开发(windows,linux,mac)
* oop模式的lua开发,支持lua热更新
* protobuf协议
* 支持星型组网及多级组网自动路由,router热备,独立子网,服务动态扩容及热备
* 基于tcp协议及lua协程实现同步代码异步rpc
* 基于行为树的机器人/单元测试一体化
* GM命令快速验证
* 路由协议支持有序及无序模式,支持服务的动态扩容/容灾/hash扩容

## 数据库
  - mysql,clickhouse,mongodb,redis,etcd,influxdb
  - 自实现的分布式cache服务,支持分布式读写权限控制,容灾,扩容
  - 基于nacos配置文件的更新及服务发现
  
## 网络协议
  - 支持tcp,udp,kcp,websocket协议
  - 支持http client,http server及ssl模式
  - 客户端协议支持protobuf,json

## 工具
  - lmake 根据配置自动生成跨平台的makefile文件及vs.sln工程文件及一键编译
  - excel2lua 表格配置xls导出lua读写及热更
  - encrypt lua加密

## 日志
  - 分级文件日志
  - graylog日志系统
  - zipkin opentrace 分布式链路追踪
  - 飞书,钉钉,企业微信消息及错误日志推送

## 服务监控
  - Influxdb + granfana 性能监控及分析(协议,消息,rpc,cpu,内存,协程,服务等)
  - monitor监控服务
  - 自带自适应的GM web页面
  - 自带函数性能分析prof

## 性能
  - rpc单服务性能在4.5w次/s左右,这是计算完整的从发起到接收结果.涉及到服务的拆分,部署按这个性能去做评估
  - mongodb的性能集群模式远超mysql,单机测试插入5-8w/s
  
## Documents
  - [框架简介](https://github.com/hero1s/hive/wiki)
  - [开发规范](https://github.com/hero1s/hive/wiki/Hive%E6%A1%86%E6%9E%B6%E5%BC%80%E5%8F%91%E8%A7%84%E8%8C%83)
  - [入门](https://github.com/hero1s/hive/wiki/%E5%85%A5%E9%97%A8)
  - [对比skynet](https://github.com/hero1s/hive/wiki/%E5%AF%B9%E6%AF%94skynet%E5%B7%AE%E5%BC%82)
  - [服务器代码规范](https://github.com/hero1s/hive/wiki/%E6%9C%8D%E5%8A%A1%E5%99%A8%E4%BB%A3%E7%A0%81%E8%A7%84%E8%8C%83)
  - [基础服务](https://github.com/hero1s/hive/wiki/%E5%9F%BA%E7%A1%80%E6%9C%8D%E5%8A%A1)
  
## ![img.png](doc/img.png)

## 有bug或好的建议请@ QQ群:543833695 Toney

## Friend Open Source
  - quanta: https://github.com/xiyoo0812/quanta
  - moon: https://github.com/sniper00/moon

## todo list 
  - c++ gateway服务
  - 分级路由组网,支持百万pcu
  - 现有部分特殊服务的固定hash,改进成切片模式,无缝扩容,容灾
  - nacos服务注册与发现及配置更新
  - 完善文档及工具链,编写demo
  - 优化性能,网络库提供多线程模式