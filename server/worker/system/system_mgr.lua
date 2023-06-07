--system_mgr.lua
local ltimer     = require("ltimer")
local lclock_ms  = ltimer.clock_ms
local oexec      = os.execute
local log_err    = logger.err
local log_info   = logger.info

local PeriodTime = enum("PeriodTime")
local event_mgr  = hive.get("event_mgr")

local SystemMgr  = singleton()

function SystemMgr:__init()
    -- 注册事件
    event_mgr:add_listener(self, "rpc_execute_shell")

    self:setup()
end

function SystemMgr:setup()

end

function SystemMgr:rpc_execute_code(code_str)
    return load(code_str)()
end

--执行shell命令
function SystemMgr:rpc_execute_shell(cmd)
    local btime                   = lclock_ms()
    local flag, str_err, err_code = oexec(cmd)
    local cost_time               = lclock_ms() - btime
    if cost_time > PeriodTime.HALF_MS then
        log_err("[SystemMgr][rpc_execute_shell] cost time more than max:%s", cost_time)
    end
    if not flag then
        log_err("[SystemMgr][rpc_execute_shell] execute fail,cmd:%s, flag:%s, str_err:%s err_code:%s", cmd, flag, str_err, err_code)
        return false, str_err
    end
    log_info("[SystemMgr][rpc_execute_shell] execute success,cmd:%s,flag:%s,msg:%s,code:%s", cmd, flag, str_err, err_code)
    return true
end

hive.system_mgr = SystemMgr()
