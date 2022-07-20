--statis_mgr.lua
import("kernel/object/linux.lua")
local InfluxDB     = import("driver/influx.lua")

local env_get      = environ.get
local env_addr     = environ.addr
local env_status   = environ.status

local event_mgr    = hive.get("event_mgr")
local update_mgr   = hive.get("update_mgr")
local thread_mgr   = hive.get("thread_mgr")
local linux_statis = hive.get("linux_statis")

local StatisMgr    = singleton()
local prop         = property(StatisMgr)
prop:reader("influx", nil)              --influx
prop:reader("statis", {})               --statis
prop:reader("statis_status", false)     --统计开关
function StatisMgr:__init()
    local statis_status = env_status("HIVE_STATIS")
    if statis_status then
        self.statis_status = statis_status
        --初始化参数
        local org          = env_get("HIVE_INFLUX_ORG")
        local token        = env_get("HIVE_INFLUX_TOKEN")
        local bucket       = env_get("HIVE_INFLUX_BUCKET")
        local ip, port     = env_addr("HIVE_INFLUX_ADDR")
        self.influx        = InfluxDB(ip, port, org, bucket, token)
        --事件监听
        event_mgr:add_listener(self, "on_rpc_send")
        event_mgr:add_listener(self, "on_rpc_recv")
        event_mgr:add_listener(self, "on_perfeval")
        event_mgr:add_listener(self, "on_proto_recv")
        event_mgr:add_listener(self, "on_proto_send")
        event_mgr:add_listener(self, "on_conn_update")
        --定时处理
        update_mgr:attach_minute(self)
        --系统监控
        if hive.platform == "linux" then
            linux_statis:setup()
        end
    end
end

-- 发送给influx
function StatisMgr:flush()
    thread_mgr:fork(function()
        local statis = self.statis
        self.statis  = {}
        self.influx:batch(statis)
    end)
end

-- 发送给influx
function StatisMgr:write(measurement, name, type, fields)
    local measure = self.statis[measurement]
    if not measure then
        measure                  = {
            tags       = {
                name    = name,
                type    = type,
                index   = hive.index,
                service = hive.service_name
            },
            field_list = {}
        }
        self.statis[measurement] = measure
    end
    measure.field_list[#measure.field_list] = fields
end

-- 统计proto协议发送(KB)
function StatisMgr:on_proto_recv(cmd_id, send_len)
    if self.statis_status then
        local fields = { count = send_len }
        self:write("network", cmd_id, "proto_recv", fields)
    end
end

-- 统计proto协议接收(KB)
function StatisMgr:on_proto_send(cmd_id, recv_len)
    if self.statis_status then
        local fields = { count = recv_len }
        self:write("network", cmd_id, "proto_send", fields)
    end
end

-- 统计rpc协议发送(KB)
function StatisMgr:on_rpc_send(rpc, send_len)
    if self.statis_status then
        local fields = { count = send_len }
        self:write("network", rpc, "rpc_send", fields)
    end
end

-- 统计rpc协议接收(KB)
function StatisMgr:on_rpc_recv(rpc, recv_len)
    if self.statis_status then
        local fields = { count = recv_len }
        self:write("network", rpc, "rpc_recv", fields)
    end
end

-- 统计cmd协议连接
function StatisMgr:on_conn_update(conn_type, conn_count)
    if self.statis_status then
        local fields = { count = conn_count }
        self:write("network", conn_type, "conn", fields)
    end
end

-- 统计性能
function StatisMgr:on_perfeval(eval_data, clock_ms)
    if self.statis_status then
        local tital_time = clock_ms - eval_data.begin_time
        local fields     = {
            tital_time = tital_time,
            yield_time = eval_data.yield_time,
            eval_time  = tital_time - eval_data.yield_time
        }
        self:write("perfeval", eval_data.eval_name, nil, fields)
    end
end

-- 统计系统信息
function StatisMgr:on_minute(now)
    if self.statis_status then
        local fields = {
            all_mem  = self:_calc_mem_use(),
            lua_mem  = self:_calc_lua_mem(),
            cpu_rate = self:_calc_cpu_rate(),
        }
        self:write("system", nil, nil, fields)
        self:flush()
    end
end

-- 计算lua内存信息(KB)
function StatisMgr:_calc_lua_mem()
    return collectgarbage("count")
end

-- 计算内存信息(KB)
function StatisMgr:_calc_mem_use()
    if hive.platform == "linux" then
        return linux_statis:calc_memory()
    end
    return 0
end

-- 计算cpu使用率
function StatisMgr:_calc_cpu_rate()
    if hive.platform == "linux" then
        return linux_statis:calc_cpu_rate()
    end
    return 0.1
end

hive.statis_mgr = StatisMgr()

return StatisMgr
