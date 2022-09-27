--service.lua
--每个服务进程都有一个唯一的进程id，由4部分组成
--1、服务类型 0-63
--2、区服信息 0-1023
--3、分组信息 0-63
--4、实例编号 0-1023
--每个服务进程都有一个唯一的服务，由2部分组成
--1、服务类型 0-63
--2、实例编号 0-1023
--变量说明
--id：          进程id      32位数字
--group：       分组信息    6-3
--index：       实例编号    0-1023
--region:       分区信息    0-1023
--servcie:      服务类型    0-63
--servcie_id:   服务id      32位数字
--service_name: 服务名      lobby
--service_nick: 服务别名    lobby.1

import("kernel/config_mgr.lua")

local sformat    = string.format

local config_mgr = hive.get("config_mgr")
local service_db = config_mgr:init_table("service", "id")

--服务组常量
local SERVICES   = _ENV.SERVICES or {}

service          = {}

function service.init()
    --加载服务配置
    for _, conf in service_db:iterator() do
        SERVICES[conf.name] = conf.id
    end
    --初始化服务信息
    local name        = environ.get("HIVE_SERVICE")
    local index       = environ.number("HIVE_INDEX", 1)
    local service_id  = service.name2sid(name)
    hive.index        = index
    hive.id           = service.make_id(name, index)
    hive.service_name = name
    hive.service_id   = service_id
    hive.name         = sformat("%s_%s", name, index)
    hive.deploy       = environ.get("HIVE_DEPLOY", "develop")
end

--生成节点id
function service.make_id(name, index)
    if type(name) == "string" then
        name = SERVICES[name]
    end
    return (name << 16) | index
end

--节点id获取服务id
function service.id2sid(hive_id)
    return (hive_id >> 16) & 0xff
end

--节点id获取服务index
function service.id2index(hive_id)
    return hive_id & 0x3ff
end

--节点id转服务名
function service.id2name(hive_id)
    return service_db:find_value("name", hive_id >> 16)
end

--服务id转服务名
function service.sid2name(service_id)
    return service_db:find_value("name", service_id)
end

--服务名转服务id
function service.name2sid(name)
    return SERVICES[name]
end

--节点id转服务昵称
function service.id2nick(hive_id)
    if hive_id == nil or hive_id == 0 then
        return "nil"
    end
    local index      = hive_id & 0x3ff
    local service_id = hive_id >> 16
    local sname      = service.sid2name(service_id)
    return sformat("%s_%s", sname, index)
end

--服务固定hash
function service.hash(service_id)
    return service_db:find_value("hash", service_id)
end

--生成router_id
function service.router_id(host_id, index)
    local router_index = host_id << 8 | index
    return service.make_id("router", router_index)
end

--生成router_name
function service.router_name(host_id, index)
    return sformat("router_%s_%s", host_id, index)
end