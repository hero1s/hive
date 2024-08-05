local log_info   = logger.info

local event_mgr  = hive.get("event_mgr")
local update_mgr = hive.get("update_mgr")

local WorkerEvt  = singleton()

function WorkerEvt:__init()
    event_mgr:add_listener(self, "on_reload")
    event_mgr:add_listener(self, "on_reload_env")
    event_mgr:add_listener(self, "rpc_count_lua_obj")
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
    local gc_mgr = hive.get("gc_mgr")
    return gc_mgr:dump_mem_obj(less_num)
end

hive.worker_evt = WorkerEvt()

return WorkerEvt
