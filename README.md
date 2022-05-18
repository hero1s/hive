# hive
基于c++,lua 实现的分布式游戏服务器框架

* 语言：c++ 、 lua
* 框架(hive)+逻辑(server)
* 支持跨平台开发(windows,linux,mac)
* 支持热更新
* protobuf协议
    - pbc修改了浮点数自动转整数的逻辑

## 目录简介

- [hive] ：hive框架
  - [bin] ：框架可执行文件
  - [core] ：框架c++代码
  - [extend] ：扩展库c++工程
  - [script] ：框架lua代码
  - [server] ：框架服务
    - [admin] : 后台管理及自动生成的GM页面
    - [cache] : 游戏数据缓存服务目前仅支持mongo
    - [monitor] : 监控服务及实时日志页面查看
    - [online] : 玩家在线服用于消息转发
    - [proxy] : http 请求代理服
    - [qtest] : 测试代码样例
    - [router] : 消息路由服,负责消息及rpc转发.目前单层星型,后续支持多层子网模式
  - [tools] ：框架工具
    - [encrypt] : lua源码加密
    - [lmake] : 自动生成makefile 及 vs工程
    - [excel2lua] : 转表工具
  - [proto]: proto协议
  - create_lmake.bat 用于生成所有c++工程
  
