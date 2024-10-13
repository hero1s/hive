--service.lua
--每个服务进程都有一个唯一的服务，由2部分组成
--1:分组信息 0-63
--1:服务类型 0-255
--2:实例编号 0-4095
--变量说明
--id：            进程id     32位整数
--group:          分组信息    0-63
--index：         编号        0-4096
--service_id:     服务        0-255
--service_name:   服务名      lobby
--service_nick:   服务别名    lobby.1

import("kernel/config_mgr.lua")
local log_err       = logger.err
local sformat       = string.format

--服务组常量
local SERVICES      = hive.init("SERVICES")
local SERVICE_NAMES = hive.init("SERVICE_NAMES")
local SERVICE_HASHS = hive.init("SERVICE_HASHS")
local SERVICE_CONFS = hive.init("SERVICE_CONFS")

service             = {}

function service.make_node(port, domain)
    hive.node_info = {
        id           = hive.id,
        name         = hive.name,
        index        = hive.index,
        group        = hive.group,
        service_id   = hive.service_id,
        service_name = hive.service_name,
        port         = port or hive.index,
        host         = domain or hive.host,
        pid          = hive.pid,
        is_ready     = false,
        status       = hive.service_status
    }
    if not hive.node_info.host or hive.node_info.host == "" then
        hive.node_info.host = "127.0.0.1"
    end
    --检测合法性
    if hive.index > 4095 or hive.index < 1 then
        log_err("service index is invalid:%s,1~4095", hive.index)
        signal.quit()
    end
    if hive.service_id > 255 or hive.service_id < 1 then
        log_err("service_id  is invalid:%s,1~255", hive.service_id)
        signal.quit()
    end
end

function service.modify_node(key, val)
    hive.node_info[key] = val
end

function service.init()
    --加载服务配置
    local config_mgr = hive.get("config_mgr")
    local service_db = config_mgr:init_table("service", "id")
    for _, conf in service_db:iterator() do
        SERVICES[conf.name]    = conf.id
        SERVICE_NAMES[conf.id] = conf.name
        SERVICE_HASHS[conf.id] = conf.hash
        SERVICE_CONFS[conf.id] = conf
    end
    config_mgr:close_table("service")
    --初始化服务信息
    local index        = environ.number("HIVE_INDEX", 1)
    local group        = environ.number("HIVE_GROUP", 1)
    local service_name = environ.get("HIVE_SERVICE")
    local service_id   = SERVICES[service_name]
    assert(service_id ~= nil, "service is not config")
    hive.index        = index
    hive.group        = group
    hive.id           = service.make_sid(service_id, index)
    hive.service_name = service_name
    hive.service_id   = service_id
    hive.name         = service.id2nick(hive.id)
    hive.host         = environ.get("HIVE_HOST_IP", "127.0.0.1")
    hive.mode         = SERVICE_CONFS[service_id].mode
    hive.rely_router  = SERVICE_CONFS[service_id].rely_router
    hive.safe_stop    = SERVICE_CONFS[service_id].safe_stop
    hive.pre_services = SERVICE_CONFS[service_id].pre_services
    hive.is_publish   = environ.status("HIVE_PUBLISH_ENV")
    hive.region       = environ.number("HIVE_CURRENT_REGION", 0)
    service.make_node()
end

--生成节点id
function service.make_id(name, index, group)
    if type(name) == "string" then
        name = SERVICES[name]
    end
    return service.make_sid(name, index, group)
end

--生成服务id
function service.make_sid(service, index, group)
    return ((group or hive.group) << 26) | (service << 16) | index
end

function service.services()
    return SERVICES
end

--节点id获取服务id
function service.id2sid(hive_id)
    return (hive_id >> 16) & 0xff
end

--节点id获取group
function service.id2group(hive_id)
    return (hive_id >> 26)
end

--节点id获取服务index
function service.id2index(hive_id)
    return hive_id & 0xfff
end

--节点id转服务名
function service.id2name(hive_id)
    return SERVICE_NAMES[(hive_id >> 16) & 0xff]
end

--服务id转服务名
function service.sid2name(service_id)
    return SERVICE_NAMES[service_id]
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
    local index      = hive_id & 0xfff
    local group      = hive_id >> 26
    local service_id = (hive_id >> 16) & 0xff
    local sname      = service.sid2name(service_id)
    return sformat("%s_%s_%s", sname, group, index)
end

--服务固定hash
function service.hash(service_id)
    return SERVICE_HASHS[service_id]
end

--唯一ip限制
function service.sole_ip(service_id)
    return SERVICE_CONFS[service_id].sole_ip
end