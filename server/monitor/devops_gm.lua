---devops_gm_mgr.lua
local lcrypt       = require("lcrypt")
local sdump        = string.dump
local log_err      = logger.err
local log_warn     = logger.warn
local log_debug    = logger.debug

local event_mgr    = hive.get("event_mgr")
local router_mgr   = hive.get("router_mgr")
local gm_agent     = hive.get("gm_agent")
local monitor_mgr  = hive.get("monitor_mgr")

local GMType       = enum("GMType")

local DevopsGmMgr  = singleton()

function DevopsGmMgr:__init()
    --注册GM指令
    self:register()
end

function DevopsGmMgr:register()
    local cmd_list = {
        { gm_type = GMType.DEV_OPS, name = "gm_set_log_level", desc = "设置日志等级", args = "svr_name|string level|integer" },
        { gm_type = GMType.DEV_OPS, name = "gm_hotfix", desc = "热更新", args = "" },
        { gm_type = GMType.DEV_OPS, name = "gm_inject", desc = "代码注入", args = "svr_name|string file_name|string base64_code|string" },
        { gm_type = GMType.DEV_OPS, name = "gm_stop_service", desc = "停服", args = "force|integer" },
    }
    for _, v in ipairs(cmd_list) do
        event_mgr:add_listener(self, v.name)
    end
    gm_agent:insert_command(cmd_list)
end

-- 设置日志等级
function DevopsGmMgr:gm_set_log_level(svr_name, level)
    log_warn("[DevopsGmMgr][gm_set_log_level] gm_set_log_level %s, %s", svr_name, level)
    return monitor_mgr:broadcast("gm_set_log_level", 0, level)
end

-- 热更新
function DevopsGmMgr:gm_hotfix()
    log_warn("[DevopsGmMgr][gm_hotfix]")
    monitor_mgr:broadcast("on_reload", 0)
    return { code = 0 }
end

function DevopsGmMgr:gm_inject(svr_name, file_name, base64_code)
    local decode_code = lcrypt.b64_decode(base64_code)
    log_debug("[DevopsGmMgr][gm_inject] svr_name:%s, file_name:%s, decode_code:%s", svr_name, file_name, decode_code)
    local ret, func = 0, nil
    if file_name ~= "" then
        func = loadfile(file_name)
    elseif base64_code ~= "" then
        func = load(decode_code)
    end

    if func and func ~= "" then
        if svr_name == "" then
            monitor_mgr:broadcast("on_inject", sdump(func))
        else
            router_mgr["send_" .. svr_name .. "_all"](router_mgr, "on_inject", sdump(func))
        end
    else
        log_err("[DevopsGmMgr][gm_inject] error file_name:%s, decode_code:%s", file_name, decode_code)
        ret = -1
    end
    return { code = ret }
end

function DevopsGmMgr:gm_stop_service(force)
    log_warn("[DevopsGmMgr][gm_stop_service]")
    monitor_mgr:broadcast("stop_service",0,force)
    return { code = 0 }
end

hive.devops_gm_mgr = DevopsGmMgr()

return DevopsGmMgr
