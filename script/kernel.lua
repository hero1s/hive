--kernel.lua
import("basic/basic.lua")
import("basic/json.lua")

local ltimer        = require("ltimer")
local lprof         = require("lprof")
local prof_manager  = lprof.new()
local ProfObj       = import("kernel/object/prof_obj.lua")

local socket_mgr    = nil
local update_mgr    = nil
local ltime         = ltimer.time

local HiveMode      = enum("HiveMode")
local ServiceStatus = enum("ServiceStatus")

--初始化网络
local function init_network()
    local lbus      = require("luabus")
    local max_conn  = environ.number("HIVE_MAX_CONN", 64)
    socket_mgr      = lbus.create_socket_mgr(max_conn)
    hive.socket_mgr = socket_mgr
end

--初始化路由
local function init_router()
    import("kernel/router_mgr.lua")
    import("driver/webhook.lua")
    import("agent/gm_agent.lua")
    import("agent/http_agent.lua")
end

--初始化loop
local function init_mainloop()
    import("kernel/thread_mgr.lua")
    import("kernel/timer_mgr.lua")
    import("kernel/update_mgr.lua")
    update_mgr = hive.get("update_mgr")
end

function hive.init()
    --初始化基础模块
    prof_manager.init()
    signal.init()
    environ.init()
    service.init()
    logger.init()
    --主循环
    init_mainloop()
    --网络
    if hive.mode < HiveMode.TINY then
        --加载统计
        import("kernel/perfeval_mgr.lua")
        import("kernel/statis_mgr.lua")
        init_network()
    end
    --其他模块加载
    if hive.mode == HiveMode.SERVICE then
        init_router()
        --加载协议
        import("kernel/protobuf_mgr.lua")
        --加载monotor
        import("agent/monitor_agent.lua")
        if not environ.get("HIVE_MONITOR_HOST") then
            import("kernel/netlog_mgr.lua")
        end
        --graylog
        logger.setup_graylog()
        import("devops/devops_mgr.lua")
    end
end

--启动
function hive.startup(entry)
    hive.now                   = 0
    hive.frame                 = 0
    hive.yield                 = coroutine.yield
    hive.resume                = coroutine.resume
    hive.running               = coroutine.running
    hive.now_ms, hive.clock_ms = ltime()
    hive.service_status        = ServiceStatus.STOP
    --初始化随机种子
    math.randomseed(hive.now_ms)
    --初始化hive
    hive.init()
    --启动服务器
    entry()
    local timer_mgr = hive.get("timer_mgr")
    timer_mgr:once(30 * 1000, function()
        hive.service_status = ServiceStatus.RUN
        logger.info("service start run status:%s",hive.name)
    end)
end

--底层驱动
hive.run      = function()
    if socket_mgr then
        socket_mgr.wait(10)
    end
    --系统更新
    update_mgr:update(ltime())
end

hive.exit     = function()
    logger.warn("prof:\n %s", prof_manager.report())
    prof_manager.shutdown()
end

--性能打点
hive.new_prof = function(key)
    return ProfObj(prof_manager, key)
end
