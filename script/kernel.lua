--kernel.lua
local ltimer  = require("ltimer")
local lhelper = require("lhelper")
import("basic/basic.lua")
import("basic/utility.lua")
import("kernel/config_mgr.lua")
import("kernel/perfeval_mgr.lua")
import("kernel/update_mgr.lua")

local ltime        = ltimer.time
local log_info     = logger.info
local env_get      = environ.get
local env_number   = environ.number
local qxpcall      = hive.xpcall
local qxpcall_quit = hive.xpcall_quit

local socket_mgr   = nil
local update_mgr   = hive.get("update_mgr")

--hive启动
function hive.ready()
    hive.frame            = 0
    hive.now_ms, hive.now = ltime()
    hive.index            = env_number("HIVE_INDEX", 1)
    hive.deploy           = env_get("HIVE_DEPLOY", "develop")
    local service_name    = env_get("HIVE_SERVICE")
    local service_id      = service.init(service_name)
    assert(service_id, "service_id not exist, hive startup failed!")
    hive.service    = service_name
    hive.service_id = service_id
    hive.id         = service.make_id(service_name, hive.index)
    hive.name       = service.make_nick(service_name, hive.index)
    hive.lan_ip     = lhelper.get_lan_ip()
end

function hive.init()
    import("basic/service.lua")
    --启动hive
    hive.ready()
    --初始化环境变量
    environ.init()
    --注册信号
    signal.init()
    --初始化日志
    logger.init()
    --初始化随机种子
    math.randomseed(hive.now_ms)

    -- 网络模块初始化
    local lbus      = require("luabus")
    local max_conn  = env_number("HIVE_MAX_CONN", 64)
    socket_mgr      = lbus.create_socket_mgr(max_conn)
    hive.socket_mgr = socket_mgr

    --初始化路由管理器
    if service.router(hive.service_id) then
        --加载router配置
        import("kernel/router_mgr.lua")
        import("driver/oanotify.lua")
    end

    -- 初始化统计管理器
    hive.perfeval_mgr:setup()
    import("kernel/statis_mgr.lua")
    import("kernel/protobuf_mgr.lua")

    if service.monitor(hive.service_id) then
        --加载monitor
        import("agent/monitor_agent.lua")
        import("kernel/netlog_mgr.lua")
    end

    if hive.router_mgr then
        import("agent/gm_agent.lua")
    end
    --graylog
    logger.setup_graylog()
end

local function startup(startup_func)
    --初始化hive
    hive.init()
    --启动服务器
    startup_func()
    log_info("%s %d now startup!", hive.service, hive.id)

    --启动后功能
    hive.after_startup()
end

--启动
function hive.startup(startup_func)
    if not hive.init_flag then
        qxpcall_quit(startup, "hive startup error: %s", startup_func)
        hive.init_flag = true
    end
end

-- 启动后
function hive.after_startup()
    import("devops/devops_mgr.lua")
end

--日常更新
local function update()
    local count         = socket_mgr.wait(10)
    local now_ms, now_s = ltime()
    hive.now            = now_s
    hive.now_ms         = now_ms
    --系统更新
    update_mgr:update(now_ms, count)
end

--底层驱动
hive.run = function()
    qxpcall(update, "hive.run error: %s")
end
