--system_mgr.lua
local ltimer          = require("ltimer")
local lhelper         = require("lhelper")
local mem_available   = lhelper.mem_available
local cpu_use_percent = lhelper.cpu_use_percent
local lclock_ms       = ltimer.clock_ms
local oexec           = os.execute
local log_err         = logger.err
local log_info        = logger.info
local cut_tail        = math_ext.cut_tail

local PeriodTime      = enum("PeriodTime")
local event_mgr       = hive.get("event_mgr")

local SystemMgr       = singleton()

function SystemMgr:__init()
    -- 注册事件
    event_mgr:add_listener(self, "rpc_execute_shell")
    event_mgr:add_listener(self, "rpc_execute_code")
    event_mgr:add_listener(self, "rpc_open_cpu_info")
    event_mgr:add_listener(self, "rpc_get_cpu_info")

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
    if cost_time > PeriodTime.SECOND_3_MS then
        log_err("[SystemMgr][rpc_execute_shell] cmd:{},cost time more than max:{}", cmd, cost_time)
    end
    if not flag then
        log_err("[SystemMgr][rpc_execute_shell] execute fail,cmd:{}, flag:{}, str_err:{} err_code:{},cost_time:{}", cmd, flag, str_err, err_code, cost_time)
        return false, str_err
    end
    log_info("[SystemMgr][rpc_execute_shell] execute success,cmd:{},flag:{},msg:{},code:{},cost_time:{}", cmd, flag, str_err, err_code, cost_time)
    return true
end

function SystemMgr:rpc_open_cpu_info(open)
    if self.timer then
        self.timer:unregister()
        self.timer = nil
    end
    if open then
        self.timer = hive.make_timer()
        self.timer:loop(PeriodTime.SECOND_2_MS, function()
            self:on_gather_cpu_tick()
        end)
    end
end

function SystemMgr:rpc_get_cpu_info()
    return self.cpu_use_percent, self.mem_total, self.mem_avail
end

function SystemMgr:on_gather_cpu_tick()
    self.cpu_use_percent           = cut_tail(cpu_use_percent(), 2, true)
    self.mem_total, self.mem_avail = mem_available()
end

hive.system_mgr = SystemMgr()
