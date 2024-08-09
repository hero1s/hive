local log_info   = logger.info

local event_mgr  = hive.get("event_mgr")
local update_mgr = hive.get("update_mgr")
local gc_mgr     = hive.get("gc_mgr")

local KernCode   = enum("KernCode")

local WorkerEvt  = singleton()

function WorkerEvt:__init()
    event_mgr:add_listener(self, "on_reload")
    event_mgr:add_listener(self, "on_reload_env")
    event_mgr:add_listener(self, "rpc_count_lua_obj")
    event_mgr:add_listener(self, "rpc_full_gc")
    event_mgr:add_listener(self, "rpc_set_gc_speed")
end

--热更新
function WorkerEvt:on_reload()
    log_info("[WorkerEvt][on_reload] worker:{} reload for signal !", hive.title)
    --重新加载脚本
    update_mgr:check_hotfix()
    --事件通知
    event_mgr:notify_trigger("on_reload")
end

--环境变量
function WorkerEvt:on_reload_env(key)
    log_info("[WorkerEvt][on_reload_env] worker:{} reload env:{}", hive.title, key)
    --事件通知
    event_mgr:notify_trigger("evt_change_env", key)
end

function WorkerEvt:rpc_count_lua_obj(less_num)
    return KernCode.SUCCESS, gc_mgr:dump_mem_obj(less_num)
end

function WorkerEvt:rpc_full_gc()
    gc_mgr:full_gc()
end

function WorkerEvt:rpc_set_gc_speed(pause, step_mul)
    gc_mgr:set_gc_speed(pause, step_mul)
end

hive.worker_evt = WorkerEvt()

return WorkerEvt
