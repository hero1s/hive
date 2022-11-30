--statis_mgr.lua
import("kernel/object/linux.lua")

local tinsert      = table.insert
local tsort        = table.sort
local env_status   = environ.status

local log_warn     = logger.warn

local event_mgr    = hive.get("event_mgr")
local update_mgr   = hive.get("update_mgr")
local linux_statis = hive.get("linux_statis")

local StatisMgr    = singleton()
local prop         = property(StatisMgr)
prop:accessor("db_agent", nil)          --数据代理
prop:reader("statis", {})               --statis
prop:reader("statis_status", false)     --统计开关
prop:reader("perfevals", {})            --性能统计
function StatisMgr:__init()
    local statis_status = env_status("HIVE_STATIS")
    if statis_status then
        self.statis_status = statis_status
        --事件监听
        event_mgr:add_listener(self, "on_rpc_send")
        event_mgr:add_listener(self, "on_rpc_recv")
        event_mgr:add_listener(self, "on_perfeval")
        event_mgr:add_listener(self, "on_proto_recv")
        event_mgr:add_listener(self, "on_proto_send")
        event_mgr:add_listener(self, "on_conn_update")
        --定时处理
        update_mgr:attach_second(self)
        update_mgr:attach_minute(self)
        update_mgr:attach_quit(self)
        --系统监控
        if hive.platform == "linux" then
            linux_statis:setup()
        end
    end
end

-- 发送给influx
function StatisMgr:flush()
    local statis = self.statis
    self.statis  = {}
    if self.db_agent and next(statis) then
        self.db_agent:write_statis(statis)
    end
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
    measure.field_list[#measure.field_list + 1] = fields
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
        local total_time = clock_ms - eval_data.begin_time
        if total_time > 0 then
            local fields = {
                total_time = total_time,
                yield_time = eval_data.yield_time,
                eval_time  = total_time - eval_data.yield_time
            }
            self:write("perfeval", eval_data.eval_name, nil, fields)
            self:write_perf(eval_data.eval_name, fields)
        end
    end
end

function StatisMgr:write_perf(eval_name, fields)
    local eval = self.perfevals[eval_name]
    if eval then
        eval.total_time    = eval.total_time + fields.total_time
        eval.yield_time    = eval.yield_time + fields.yield_time
        eval.eval_time     = eval.eval_time + fields.eval_time
        eval.max_eval_time = (fields.eval_time > eval.max_eval_time) and fields.eval_time or eval.max_eval_time
        eval.count         = eval.count + 1
    else
        self.perfevals[eval_name] = {
            total_time    = fields.total_time,
            yield_time    = fields.yield_time,
            eval_time     = fields.eval_time,
            max_eval_time = fields.eval_time,
            count         = 1
        }
    end
end

function StatisMgr:dump_perf()
    local sort_infos = {}
    for i, v in pairs(self.perfevals) do
        local info = {
            name          = i,
            total_time    = v.total_time / v.count,
            yield_time    = v.yield_time / v.count,
            eval_time     = v.eval_time / v.count,
            max_eval_time = v.max_eval_time,
            count         = v.count
        }
        tinsert(sort_infos, info)
    end
    tsort(sort_infos, function(a, b)
        return a.total_time > b.total_time
    end)
    if next(sort_infos) then
        log_warn("[StatisMgr][dump_perf] \n %s", sort_infos)
    end
end

function StatisMgr:on_second()
    self:flush()
end

-- 统计系统信息
function StatisMgr:on_minute()
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

function StatisMgr:on_quit()
    self:dump_perf()
end

hive.statis_mgr = StatisMgr()

return StatisMgr
