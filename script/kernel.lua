--kernel.lua
import("basic/basic.lua")
import("kernel/mem_monitor.lua")
local lbus          = require("luabus")
local ltimer        = require("ltimer")

local tpack         = table.pack
local tunpack       = table.unpack
local log_err       = logger.err
local raw_yield     = coroutine.yield
local raw_resume    = coroutine.resume
local lclock_ms     = ltimer.clock_ms
local ltime         = ltimer.time

local HiveMode      = enum("HiveMode")
local ServiceStatus = enum("ServiceStatus")

local co_hookor     = hive.load("co_hookor")
local scheduler     = hive.load("scheduler")
local update_mgr    = hive.load("update_mgr")
local event_mgr     = hive.load("event_mgr")

local HALF_MS       = hive.enum("PeriodTime", "HALF_MS")

--初始化核心
local function init_core()
    import("kernel/gc_mgr.lua")
    import("kernel/thread_mgr.lua")
    import("kernel/event_mgr.lua")
    import("kernel/config_mgr.lua")
end

--初始化网络
local function init_network()
    local max_conn = environ.number("HIVE_MAX_CONN", 4096)
    local rpc_key  = environ.get("HIVE_RPC_KEY", "hive2022")
    lbus.init_socket_mgr(max_conn)
    lbus.set_rpc_key(rpc_key)
end

--初始化路由
local function init_router()
    import("kernel/router_mgr.lua")
    import("agent/gm_agent.lua")
end

--加载monitor
local function init_monitor()
    import("agent/monitor_agent.lua")
    import("agent/discovery_agent.lua")
    if not environ.get("HIVE_MONITOR_HOST") then
        import("kernel/netlog_mgr.lua")
    end
end

--协程改造
local function init_coroutine()
    coroutine.yield  = function(...)
        if co_hookor then
            co_hookor:yield()
        end
        return raw_yield(...)
    end
    coroutine.resume = function(co, ...)
        if co_hookor then
            co_hookor:yield()
            co_hookor:resume(co)
        end
        local args = tpack(raw_resume(co, ...))
        if co_hookor then
            co_hookor:resume()
        end
        return tunpack(args)
    end
    hive.eval        = function(name)
        if co_hookor then
            return co_hookor:eval(name)
        end
    end
end

--初始化loop
local function init_mainloop()
    import("kernel/timer_mgr.lua")
    import("kernel/update_mgr.lua")
    import("driver/scheduler.lua")
    event_mgr  = hive.get("event_mgr")
    update_mgr = hive.get("update_mgr")
    scheduler  = hive.get("scheduler")
end

--初始化统计
local function init_statis()
    import("agent/proxy_agent.lua")
    import("kernel/perfeval_mgr.lua")
end

function hive.init()
    --核心加载
    init_core()
    --初始化基础模块
    signal.init()
    environ.init()
    service.init()
    logger.init()
    logger.info("hive init run version:[%s] \n", environ.get("COMMIT_VERSION"))
    --主循环
    init_coroutine()
    init_mainloop()
    init_network()
    init_statis()
    if hive.mode <= HiveMode.ROUTER then
        --加载monotor
        init_monitor()
    end
    --其他模块加载
    if hive.mode == HiveMode.SERVICE then
        init_router()
    end
    --加载协议
    import("kernel/protobuf_mgr.lua")
    --挂载运维附加逻辑
    import("devops/devops_mgr.lua")
end

function hive.hook_coroutine(hooker)
    co_hookor      = hooker
    hive.co_hookor = hooker
end

--启动
function hive.startup(entry)
    hive.frame                 = 0
    hive.now_ms, hive.clock_ms = ltime()
    hive.now                   = hive.now_ms // 1000
    hive.service_status        = ServiceStatus.READY
    --初始化随机种子
    math.randomseed(hive.now_ms)
    --初始化hive
    hive.init()
    --启动服务器
    entry()
    hive.after_start()
end

--启动后
function hive.after_start()
    local timer_mgr = hive.get("timer_mgr")
    timer_mgr:once(1000, function()
        hive.change_service_status(ServiceStatus.RUN)
    end)
    update_mgr:update(scheduler, ltime())
    --开启debug模式
    if environ.status("HIVE_DEBUG") then
        hive.check_endless_loop()
    end
end

--变更服务状态
function hive.change_service_status(status)
    hive.service_status     = status
    hive.node_info.is_ready = hive.is_ready()
    hive.node_info.status   = hive.service_status
    logger.warn("[hive][change_service_status] %s,service_status:%s,is_ready:%s", hive.name, status, hive.is_ready())
    event_mgr:notify_trigger("evt_change_service_status", hive.service_status)
end

function hive.is_runing()
    if hive.service_status < ServiceStatus.RUN or hive.service_status > ServiceStatus.BUSY then
        return false
    end
    return hive.is_ready()
end

function hive.status_run()
    if hive.service_status == ServiceStatus.RUN or hive.service_status == ServiceStatus.BUSY then
        return true
    end
    return false
end

function hive.is_ready()
    if hive.rely_router then
        local router_mgr = hive.get("router_mgr")
        return router_mgr:is_ready()
    end
    return true
end

--底层驱动
hive.run  = function()
    local sclock_ms = lclock_ms()
    scheduler:update()
    lbus.wait(10)
    --系统更新
    local now_ms, clock_ms = ltime()
    update_mgr:update(scheduler, now_ms, clock_ms)
    --时间告警
    local work_ms = lclock_ms() - sclock_ms
    if work_ms > HALF_MS then
        local io_ms = clock_ms - sclock_ms
        log_err("[hive][run] last frame(%s) too long => all:%d, net:%d)!", hive.name, work_ms, io_ms)
    end
end

hive.exit = function()

end
