--kernel.lua
import("basic/basic.lua")
import("basic/json.lua")

local ltimer        = require("ltimer")
local lprof         = require("lprof")
local ProfObj       = import("kernel/object/prof_obj.lua")

local tpack         = table.pack
local tunpack       = table.unpack
local raw_yield     = coroutine.yield
local raw_resume    = coroutine.resume
local ltime         = ltimer.time
local lclock_ms     = ltimer.clock_ms

local HiveMode      = enum("HiveMode")
local ServiceStatus = enum("ServiceStatus")

local co_hookor     = hive.load("co_hookor")
local socket_mgr    = hive.load("socket_mgr")
local update_mgr    = hive.load("update_mgr")

--初始化网络
local function init_network()
    local lbus     = require("luabus")
    local max_conn = environ.number("HIVE_MAX_CONN", 4096)
    local rpc_key  = environ.get("HIVE_RPC_KEY", "hive2022")
    socket_mgr     = lbus.create_socket_mgr(max_conn)
    socket_mgr.set_rpc_key(rpc_key)
    hive.socket_mgr = socket_mgr
end

--初始化路由
local function init_router()
    import("kernel/router_mgr.lua")
    import("agent/gm_agent.lua")
end

--加载monitor
local function init_monitor()
    if environ.status("HIVE_JOIN_MONITOR") then
        import("agent/monitor_agent.lua")
        if not environ.get("HIVE_MONITOR_HOST") then
            import("kernel/netlog_mgr.lua")
        end
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
    import("kernel/thread_mgr.lua")
    import("kernel/timer_mgr.lua")
    import("kernel/update_mgr.lua")
    update_mgr = hive.get("update_mgr")
end

--初始化调度器
local function init_scheduler()
    import("driver/scheduler.lua")
    hive.scheduler:setup("hive")
    import("agent/proxy_agent.lua")
end

function hive.init()
    --初始化基础模块
    lprof.init()
    signal.init()
    environ.init()
    service.init()
    logger.init()
    --主循环
    init_coroutine()
    init_mainloop()
    --网络
    if hive.mode < HiveMode.TINY then
        --加载统计
        import("kernel/perfeval_mgr.lua")
        import("kernel/statis_mgr.lua")
        init_network()
        --加载协议
        import("kernel/protobuf_mgr.lua")
    end
    --其他模块加载
    if hive.mode == HiveMode.SERVICE then
        init_router()
        --加载调度器
        init_scheduler()
        --加载monotor
        init_monitor()
        --挂载运维附加逻辑
        import("devops/devops_mgr.lua")
    end
end

function hive.hook_coroutine(hooker)
    co_hookor      = hooker
    hive.co_hookor = hooker
end

--启动
function hive.startup(entry)
    hive.now                   = os.time()
    hive.frame                 = 0
    hive.now_ms, hive.clock_ms = ltime()
    hive.service_status        = ServiceStatus.STOP
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
    timer_mgr:once(10 * 1000, function()
        hive.service_status = ServiceStatus.RUN
        logger.info("service start run status:%s", hive.name)
    end)
    update_mgr:update(ltime())
    --开启debug模式
    local debug = environ.number("HIVE_DEBUG", 0)
    if debug == 1 then
        hive.check_endless_loop()
    end
end

local wait_ms = 10
--底层驱动
hive.run      = function()
    if socket_mgr then
        socket_mgr.wait(wait_ms)
    end
    --系统更新
    local now_ms, clock_ms = ltime()
    update_mgr:update(now_ms, clock_ms)
    local cost_time = lclock_ms() - clock_ms
    wait_ms         = cost_time > 10 and 1 or 10 - cost_time
end

hive.exit     = function()
    logger.warn("prof:\n %s", lprof.report())
    lprof.shutdown()
end

--性能打点
hive.new_prof = function(key)
    return ProfObj(lprof, key)
end
