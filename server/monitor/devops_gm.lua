---devops_gm_mgr.lua
local lstdfs    = require('lstdfs')
local lguid     = require("lguid")
local sdump     = string.dump
local log_err   = logger.err
local log_warn  = logger.warn
local log_debug = logger.debug
local time_str  = datetime_ext.time_str
local ssplit    = string_ext.split

import("network/http_client.lua")
local http_client   = hive.get("http_client")
local env_get       = environ.get

local event_mgr     = hive.get("event_mgr")
local gm_agent      = hive.get("gm_agent")
local monitor_mgr   = hive.get("monitor_mgr")
local timer_mgr     = hive.get("timer_mgr")

local GMType        = enum("GMType")
local ServiceStatus = enum("ServiceStatus")
local DevopsGmMgr   = singleton()

function DevopsGmMgr:__init()
    --注册GM指令
    self:register_gm()
end

function DevopsGmMgr:register_gm()
    local cmd_list = {
        { gm_type = GMType.DEV_OPS, name = "gm_set_log_level", desc = "设置日志等级", comment = "(all/全部,日志等级debug[1]-fatal[6])", args = "svr_name|string level|integer" },
        { gm_type = GMType.DEV_OPS, name = "gm_hotfix", desc = "代码热更新", args = "" },
        { gm_type = GMType.DEV_OPS, name = "gm_inject", desc = "代码注入", args = "svr_name|string file_name|string code_content|string" },
        { gm_type = GMType.DEV_OPS, name = "gm_set_server_status", desc = "设置服务器状态", comment = "[0运行1禁开局2强退],延迟(秒)", args = "status|integer delay|integer" },
        { gm_type = GMType.DEV_OPS, name = "gm_hive_quit", desc = "关闭服务器", comment = "[杀进程],延迟(秒)", args = "reason|integer delay|integer" },
        { gm_type = GMType.DEV_OPS, name = "gm_cfg_reload", desc = "配置表热更新", comment = "(0 本地 1 远程)", args = "is_remote|integer" },
        --工具
        { gm_type = GMType.TOOLS, name = "gm_guid_view", desc = "guid信息", comment = "(拆解guid)", args = "guid|integer" },
    }
    for _, v in ipairs(cmd_list) do
        event_mgr:add_listener(self, v.name)
    end
    gm_agent:insert_command(cmd_list)
end

-- 设置日志等级
function DevopsGmMgr:gm_set_log_level(svr_name, level)
    log_warn("[DevopsGmMgr][gm_set_log_level] gm_set_log_level %s, %s", svr_name, level)
    if level < 1 or level > 6 then
        return { code = 1, msg = "level not in ragne 1~6" }
    end
    return monitor_mgr:broadcast("rpc_set_log_level", svr_name, level)
end

-- 热更新
function DevopsGmMgr:gm_hotfix()
    log_warn("[DevopsGmMgr][gm_hotfix]")
    monitor_mgr:broadcast("rpc_reload")
    return { code = 0 }
end

function DevopsGmMgr:gm_inject(svr_name, file_name, code_content)
    log_debug("[DevopsGmMgr][gm_inject] svr_name:%s, file_name:%s, code_content:%s", svr_name, file_name, code_content)
    local func = nil
    if file_name ~= "" then
        func = loadfile(file_name)
    elseif code_content ~= "" then
        func = load(code_content)
    end
    if func and func ~= "" then
        return monitor_mgr:broadcast("rpc_inject", svr_name, sdump(func))
    end
    log_err("[DevopsGmMgr][gm_inject] error file_name:%s, code_content:%s", file_name, code_content)
    return { code = -1 }
end

function DevopsGmMgr:gm_set_server_status(status, delay)
    log_warn("[DevopsGmMgr][gm_set_server_status]:%s,exe time:%s ", status, time_str(hive.now + delay))
    if status < ServiceStatus.RUN or status > ServiceStatus.STOP then
        return { code = 1, msg = "status is more than" }
    end
    timer_mgr:once(delay * 1000, function()
        monitor_mgr:broadcast("rpc_set_server_status", 0, status)
    end)
    return { code = 0 }
end

function DevopsGmMgr:gm_hive_quit(reason, delay)
    log_warn("[DevopsGmMgr][gm_hive_quit] exit hive exe time:%s ", time_str(hive.now + delay))
    timer_mgr:once(delay * 1000, function()
        monitor_mgr:broadcast("rpc_hive_quit", 0, reason)
    end)
    return { code = 0 }
end

function DevopsGmMgr:gm_cfg_reload(is_remote)
    log_debug("[DevopsGmMgr][gm_cfg_reload] is_remote:%s", is_remote)
    local flag = (is_remote == 1)
    if flag then
        local url = env_get("HIVE_CONFIG_RELOAD_URL", "")
        if url == "" then
            return
        end
        -- 查看本地文件路径下的所有配置文件
        -- 遍历配置表，依次查询本地文件是否存在远端
        -- 存在则拉取并覆盖

        local current_path = lstdfs.current_path()
        local cfg_path     = current_path .. "/../server/config/"
        local cur_dirs     = lstdfs.dir(cfg_path)
        for _, file in pairs(cur_dirs) do
            local full_file_name  = file.name
            local split_arr       = ssplit(full_file_name, "/")
            local file_name       = split_arr[#split_arr]
            local remote_file_url = url .. "/" .. file_name
            local ok, status, res = http_client:call_get(remote_file_url)
            if ok and status == 200 then
                io_ext.writefile(full_file_name, res)
            end
        end
    end
    monitor_mgr:broadcast("rpc_config_reload")

    return { code = 0 }
end

function DevopsGmMgr:gm_guid_view(guid)
    local group, index, time = lguid.guid_source(guid)
    local group_h, group_l   = (group >> 4) & 0xf, group & 0xf

    return { group = group, group_h = group_h, group_l = group_l, index = index, time = datetime_ext.time_str(time) }
end

hive.devops_gm_mgr = DevopsGmMgr()

return DevopsGmMgr
