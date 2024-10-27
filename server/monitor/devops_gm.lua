---devops_gm_mgr.lua
local log_err       = logger.err
local log_warn      = logger.warn
local log_debug     = logger.debug
local time_str      = datetime_ext.time_str
local sname2sid     = service.name2sid
local smatch        = string.match
local otime         = os.time
local json_decode   = hive.json_decode
local check_success = hive.success

local gm_agent      = hive.get("gm_agent")
local monitor_mgr   = hive.get("monitor_mgr")
local timer_mgr     = hive.get("timer_mgr")
local thread_mgr    = hive.get("thread_mgr")
local mongo_agent   = hive.get("mongo_agent")
local redis_agent   = hive.get("redis_agent")

local GMType        = enum("GMType")
local ServiceStatus = enum("ServiceStatus")
local DevopsGmMgr   = singleton()

function DevopsGmMgr:__init()
    --注册GM指令
    self:register_gm()
end

function DevopsGmMgr:register_gm()
    local cmd_list = {
        { group = "运维", gm_type = GMType.GLOBAL, name = "gm_set_log_level", desc = "设置日志等级", comment = "(all/全部,日志等级debug[1]-fatal[6])", args = "svr_name|string level|integer" },
        { group = "开发工具", gm_type = GMType.GLOBAL, name = "gm_offset_time", desc = "设置服务偏移时间(s)", args = "offset|integer" },
        { group = "开发工具", gm_type = GMType.GLOBAL, name = "gm_offset_value", desc = "获取偏移时间(s)", args = "" },
        { group = "开发工具", gm_type = GMType.GLOBAL, name = "gm_set_time", desc = "设置服务器时间为指定时间", comment = " 格式：2024-08-23 12:00:00", args = "cur_time|string" },
        { group = "运维", gm_type = GMType.GLOBAL, name = "gm_hotfix", desc = "代码热更新", args = "" },
        { group = "运维", gm_type = GMType.GLOBAL, name = "gm_set_env", desc = "设置环境变量", comment = "临时修改环境变量",
          args  = "key|string value|string service_name|string index|integer" },
        { group = "运维", gm_type = GMType.GLOBAL, name = "gm_reload_env", desc = "reload环境变量", comment = "reload环境变量",
          args  = "service_name|string index|integer" },
        { group = "运维", gm_type = GMType.GLOBAL, name = "gm_set_server_status", desc = "设置服务器状态", comment = "[1运行2繁忙3挂起4强退],延迟(秒),服务/index",
          args  = "status|integer delay|integer service_name|string index|integer" },
        { group = "运维", gm_type = GMType.GLOBAL, name = "gm_query_server_online", desc = "查询在线服务", comment = "", args = "service_name|string" },
        { group = "运维", gm_type = GMType.GLOBAL, name = "gm_hive_quit", desc = "关闭服务器", comment = "强踢玩家并停服", args = "reason|integer" },
        { group = "开发工具", gm_type = GMType.GLOBAL, name = "gm_full_gc", desc = "lua全量gc", comment = "服务/index", args = "service_name|string index|integer" },
        { group = "开发工具", gm_type = GMType.GLOBAL, name = "gm_count_obj", desc = "lua对象计数", comment = "最小个数,服务/index",
          args  = "less_num|integer service_name|string index|integer" },
        { group = "开发工具", gm_type = GMType.GLOBAL, name = "gm_set_gc_step", desc = "设置gc步长,open[0,1,2],自动|混合|手动", comment = "服务/index",
          args  = "service_name|string index|integer open|integer slow|integer fast|integer" },
        { group = "开发工具", gm_type = GMType.GLOBAL, name = "gm_check_endless_loop", desc = "检测死循环", comment = "开启/关闭,服务/index",
          args  = "start|integer service_name|string index|integer" },
        { group = "开发工具", gm_type = GMType.GLOBAL, name = "gm_table_find_one", desc = "查询表格配置", comment = "表名/索引,服务/index",
          args  = "tname|string tindex|string service_name|string index|integer" },
        --工具
        { group = "开发工具", gm_type = GMType.GLOBAL, name = "gm_guid_view", desc = "guid信息", comment = "(拆解guid)", args = "guid|integer" },
        { group = "开发工具", gm_type = GMType.GLOBAL, name = "gm_log_format", desc = "日志格式", comment = "0压缩,1格式化", args = "data|string swline|integer json|integer" },
        { group = "开发工具", gm_type = GMType.GLOBAL, name = "gm_db_get", desc = "数据库查询",
          args  = "db_name|string table_name|string key_name|string key_value|string" },
        { group = "开发工具", gm_type = GMType.GLOBAL, name = "gm_db_set", desc = "数据库更新",
          args  = "db_name|string table_name|string key_name|string key_value|string json_value|string" },
        { group = "开发工具", gm_type = GMType.GLOBAL, name = "gm_redis_command", desc = "执行redis命令", comment = "示例[\"sadd\", \"global:random_nicks\", \"小李飞刀\"]", args = "command|string" },
    }
    gm_agent:insert_command(cmd_list, self)
end

function DevopsGmMgr:gm_set_time(cur_time)
    local target_time                      = 0
    local year, month, day, hour, min, sec = smatch(cur_time, "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
    if year and month and day and hour and min and sec then
        target_time = otime({ day = day, month = month, year = year, hour = hour, min = min, sec = sec })
    end
    if target_time <= 0 then
        return { code = 1, msg = "time format error" }
    end
    local offset = target_time - os.time()
    return self:gm_offset_time(offset)
end

-- 设置日志等级
function DevopsGmMgr:gm_set_log_level(svr_name, level)
    log_warn("[DevopsGmMgr][gm_set_log_level] gm_set_log_level {}, {}", svr_name, level)
    if level < 1 or level > 6 then
        return { code = 1, msg = "level not in ragne 1~6" }
    end
    return monitor_mgr:broadcast("rpc_set_log_level", svr_name, level)
end

-- 服务器时间偏移
function DevopsGmMgr:gm_offset_time(offset)
    log_warn("[DevopsGmMgr][gm_offset_time] {}", offset)
    monitor_mgr:broadcast("rpc_offset_time", 0, offset)
    timer.offset(offset)
    thread_mgr:sleep(100)
    return { code = 0, time = time_str(hive.now), offset = offset }
end

function DevopsGmMgr:gm_offset_value()
    return { code = 0, offset = timer.offset_value(), hive_now = time_str(hive.now), sys_now = time_str(os.time()) }
end

-- 热更新
function DevopsGmMgr:gm_hotfix()
    log_warn("[DevopsGmMgr][gm_hotfix]")
    monitor_mgr:broadcast("rpc_reload")
    return { code = 0 }
end

function DevopsGmMgr:gm_set_env(key, value, service_name, index)
    log_warn("[DevopsGmMgr][gm_set_env]:[{}:{}],service:{},index:{} ",
            key, value, service_name, index)
    return self:call_service_index(service_name, index, "rpc_set_env", key, value)
end

function DevopsGmMgr:gm_reload_env(service_name, index)
    log_warn("[DevopsGmMgr][gm_reload_env] service:{},index:{} ", service_name, index)
    return self:call_service_index(service_name, index, "rpc_reload_env")
end

function DevopsGmMgr:gm_set_server_status(status, delay, service_name, index)
    log_warn("[DevopsGmMgr][gm_set_server_status]:{},exe time:{},service:{},index:{} ",
            status, time_str(hive.now + delay), service_name, index)
    if status < ServiceStatus.RUN or status > ServiceStatus.STOP then
        return { code = 1, msg = "status is more than" }
    end
    timer_mgr:once(delay * 1000, function()
        self:call_service_index(service_name, index, "rpc_set_server_status", status)
    end)
    return { code = 0 }
end

function DevopsGmMgr:gm_query_server_online(service_name)
    local sids, count = monitor_mgr:query_services(service_name)
    return { sids = sids, count = count }
end

function DevopsGmMgr:gm_hive_quit(reason)
    log_warn("[DevopsGmMgr][gm_hive_quit] exit hive exe time:{} ", time_str(hive.now))
    monitor_mgr:broadcast("rpc_hive_quit", 0, reason)
    return { code = 0 }
end

function DevopsGmMgr:gm_full_gc(service_name, index)
    self:call_service_index(service_name, index, "rpc_full_gc")
    return { code = 0 }
end

function DevopsGmMgr:gm_count_obj(less_num, service_name, index)
    return self:call_target_rpc(service_name, index, "rpc_count_lua_obj", less_num)
end

function DevopsGmMgr:gm_set_gc_step(service_name, index, open, slow_step, fast_step)
    self:call_service_index(service_name, index, "rpc_set_gc_step", open, slow_step, fast_step)
    return { code = 0 }
end

function DevopsGmMgr:gm_check_endless_loop(start, service_name, index)
    self:call_service_index(service_name, index, "rpc_check_endless_loop", start == 1 and true or false)
    return { code = 0 }
end

function DevopsGmMgr:gm_table_find_one(tname, tindex, service_name, index)
    return self:call_target_rpc(service_name, index, "rpc_table_find_one", tname, tindex)
end

function DevopsGmMgr:gm_guid_view(guid)
    local group, index, gtype, time, serial = codec.guid_source(guid)
    return { group = group, gtype = gtype, index = index, time = time_str(time), serial = serial }
end

function DevopsGmMgr:gm_log_format(data, swline, json)
    if type(data) ~= "string" then
        return "格式错误"
    end
    if type(swline) ~= "number" then
        swline = 0
    end
    local data_t = luakit.unserialize(data)
    if json == 1 then
        return hive.json_encode(data_t, nil, swline == 1)
    end
    return luakit.serialize(data_t, swline)
end

function DevopsGmMgr:gm_db_get(db_name, table_name, key_name, key_value)
    log_debug("[DevopsGmMgr][gm_db_get] db_name:{}, table_name:{}, key_name:{}, key_value:{}", db_name, table_name, key_name, key_value)
    local ok, result = mongo_agent:load_sheet(table_name, tonumber(key_value), key_name, nil, db_name)
    if not ok then
        return { code = -1 }
    else
        return { code = 0, data = result }
    end
end

function DevopsGmMgr:gm_db_set(db_name, table_name, key_name, key_value, json_str)
    log_debug("[DevopsGmMgr][gm_db_set] db_name:{}, table_name:{}, key_name:{} key_value:{}, json_str:{}",
            db_name, table_name, key_name, key_value, json_str)
    local ok1, value = json_decode(json_str, true)
    if not ok1 then
        return { code = -1 }
    end
    return mongo_agent:update_sheet(table_name, tonumber(key_value), key_name, value, db_name)
end

function DevopsGmMgr:gm_redis_command(command_str)
    local ok, command = json_decode(command_str, true)
    if not ok then
        return { code = -1 }
    end
    local ok1, code, res = redis_agent:execute(command)
    if not check_success(code, ok) then
        log_err("[DevopsGmMgr][gm_redis_command] execute redis command [{}] faild:{},code:{},res:{}", command, ok1, code, res)
    else
        log_warn("[DevopsGmMgr][gm_redis_command] execute redis command [{}],res:{}", command, res)
    end
    return { code = code, res = res }
end

function DevopsGmMgr:get_target_id(service_name, index)
    if service_name ~= "" and index ~= 0 then
        local service_id = sname2sid(service_name)
        if service_id then
            return service.make_sid(service_id, index)
        end
    end
end

function DevopsGmMgr:call_target_rpc(service_name, index, rpc, ...)
    local target_id = self:get_target_id(service_name, index)
    if not target_id then
        return { code = 1, msg = "the service_name is error" }
    end
    return monitor_mgr:call_by_sid(target_id, rpc, ...)
end

function DevopsGmMgr:call_service_index(service_name, index, rpc, ...)
    log_debug("[DevopsGmMgr][call_service_index] call:{},index:{},rpc:{}", service_name, index, rpc)
    local service_id = 0
    if service_name ~= "" then
        service_id = sname2sid(service_name)
        if not service_id then
            return { code = 1, msg = "the service_name is error" }
        end
    end
    if service_id > 0 and index ~= 0 then
        --指定目标
        local target_id = service.make_sid(service_id, index)
        return monitor_mgr:send_by_sid(target_id, rpc, ...)
    else
        monitor_mgr:broadcast(rpc, service_id, ...)
    end
    return { code = 0 }
end

hive.devops_gm_mgr = DevopsGmMgr()

return DevopsGmMgr
