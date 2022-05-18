
# hive框架开发规范

## 一 业务服务器抽象类型

1. service：单例对象，负责和客户端交互，处理PB协议，同时负责和其他业务服务器交互，处理RPC协议。
2. object：业务相关实体对象，提供实体数据管理和接口管理。
3. component：组件接口，不可实例化，附加到object上。实体功能较多的时候，将高度聚合的部分功能抽象到组件。
4. manager：单例对象，负责管理实体对象。
5. dao：单例对象，数据库访问对象，负责数据存取。
6. const：常量定义文件，定义业务服务需要的常量。
7. init：业务服务器初始化文件，引用此服务器需要使用的类。

## 二 业务服务器文件规范

业务服务器存在多个service或者代码文件超过8个，需要建立二级目录。

1. sevice：所有service对象存放到此目录。
2. object/entity：所有object对象存放到此目录，当有多个类型的object或者object大于8个，需要根据object类型建立三级目录。
3. mamager：所有mamager对象存放到此目录。建议manager数量大于3个的时候，建立此目录，小于3个可以存放到object目录。
4. dao：所有dao对象存放到此目录。当dao对象大于3个时建议建立此目录。
5. init文件和const文件一个业务服务器只能有一个，放到一级目录。

## 三 事件通知规范

1. 传播方式：trigger（多播）和listener（单播）
2. 传播来源：local（本地）和remote（远程）
3. 命名规则：本地事件以evt_xxx命名，远程事件以rpc_xxx命名，客户端协议以on_xxx命名，离线消息以off_xxx命名。

## 四 业务开发规范

1. dx协议处理和分发，必须在service处理。
2. 实体和组件只管数据，提供接口，不负责业务逻辑处理。
3. errcode应该只能存在与dao和service这两个和外部交互的模块。
4. 常量尽量使用enum

## 五 文件头常量变量定义

1. 优先定义系统函数本地化变量。
2. 然后定义框架层函数本地化变量。
3. 然后定义框架层本地化变量。
4. 最后定义各种常量。

```lua
--server_mgr.lua
--系统函数本地化变量
local pairs         = pairs
local xpcall        = xpcall
local mhuge         = math.huge
--框架层函数本地化变量
local log_err       = logger.err
local log_info      = logger.info
local log_warn      = logger.warn
local env_addr      = environ.addr
local sid2name      = service.id2name
local sget_group    = service.get_group
local smake_id      = service.make_id
local services      = service.groups
local hxpcall       = hive.xpcall
--框架层本地化变量
local socket_mgr    = hive.socket_mgr
--各种常量
local SERVICE_TIMEOUT   = 10000
local RPC_FAILED        = err.Code.RPC_FAILED
```
## 六 插件工程

1. plugins插件为静态编译,尽量是c++库带namespace,并且线程安全.代码量小的核心库
2. 第三方库,c库,线程不安全,业务库都独立工程编译dll

