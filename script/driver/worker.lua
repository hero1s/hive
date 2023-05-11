--worker.lua
import("basic/basic.lua")
import("kernel/mem_monitor.lua")
import("kernel/config_mgr.lua")
local lcodec           = require("lcodec")
local ltimer           = require("ltimer")

local pcall            = pcall
local hxpcall          = hive.xpcall
local log_info         = logger.info
local log_err          = logger.err
local tpack            = table.pack
local tunpack          = table.unpack
local raw_yield        = coroutine.yield
local raw_resume       = coroutine.resume
local lencode          = lcodec.encode_slice
local ldecode          = lcodec.decode_slice
local ltime            = ltimer.time

local event_mgr        = hive.get("event_mgr")
local co_hookor        = hive.load("co_hookor")
local socket_mgr       = hive.load("socket_mgr")
local update_mgr       = hive.load("update_mgr")
local thread_mgr       = hive.load("thread_mgr")

local WTITLE           = hive.worker_title
local FLAG_REQ         = hive.enum("FlagMask", "REQ")
local FLAG_RES         = hive.enum("FlagMask", "RES")
local RPC_CALL_TIMEOUT = hive.enum("NetwkTime", "RPC_CALL_TIMEOUT")

--初始化网络
local function init_network()
    local lbus      = require("luabus")
    local max_conn  = environ.number("HIVE_MAX_CONN", 4096)
    socket_mgr      = lbus.create_socket_mgr(max_conn)
    hive.socket_mgr = socket_mgr
end

--初始化统计
local function init_statis()
    import("agent/proxy_agent.lua")
    import("kernel/perfeval_mgr.lua")
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
    thread_mgr = hive.get("thread_mgr")
    update_mgr = hive.get("update_mgr")
end

function hive.init()
    --初始化基础模块
    environ.init()
    service.init()
    --主循环
    init_coroutine()
    init_mainloop()
    --加载统计
    init_statis()
    --网络
    init_network()
    --加载协议
    import("kernel/protobuf_mgr.lua")
end

function hive.hook_coroutine(hooker)
    co_hookor      = hooker
    hive.co_hookor = hooker
end

--启动
function hive.startup(entry)
    hive.now                   = 0
    hive.frame                 = 0
    hive.now_ms, hive.clock_ms = ltime()
    --初始化随机种子
    math.randomseed(hive.now_ms)
    --初始化hive
    hive.init()
    --启动服务器
    entry()
end

--底层驱动
hive.run = function()
    if socket_mgr then
        socket_mgr.wait(10)
    end
    --系统更新
    hxpcall(function()
        hive.update()
        update_mgr:update(nil, ltime())
    end)
end

--事件分发
local function notify_rpc(session_id, title, rpc, ...)
    if rpc == "on_reload" then
        log_info("[Worker][on_reload]worker:%s reload for signal !", WTITLE)
        --重新加载脚本
        update_mgr:check_hotfix()
        return
    end
    local rpc_datas = event_mgr:notify_listener(rpc, ...)
    if session_id > 0 then
        hive.call(title, lencode(session_id, FLAG_RES, tunpack(rpc_datas)))
    end
end

--事件分发
local function worker_rpc(session_id, flag, ...)
    if flag == FLAG_REQ then
        notify_rpc(session_id, ...)
    else
        thread_mgr:response(session_id, ...)
    end
end

--rpc调用
hive.on_worker   = function(slice)
    local rpc_res = tpack(pcall(ldecode, slice))
    if not rpc_res[1] then
        log_err("[hive][on_worker] decode failed %s!", rpc_res[2])
        return
    end
    thread_mgr:fork(function()
        worker_rpc(tunpack(rpc_res, 2))
    end)
end

--访问主线程
hive.call_master = function(rpc, ...)
    local session_id = thread_mgr:build_session_id()
    hive.call("master", lencode(session_id, FLAG_REQ, WTITLE, rpc, ...))
    return thread_mgr:yield(session_id, "call_master", RPC_CALL_TIMEOUT)
end

--通知主线程
hive.send_master = function(rpc, ...)
    hive.call("master", lencode(0, FLAG_REQ, WTITLE, rpc, ...))
end

--访问其他线程
hive.call_worker = function(name, rpc, ...)
    local session_id = thread_mgr:build_session_id()
    hive.call(name, lencode(session_id, FLAG_REQ, WTITLE, rpc, ...))
    return thread_mgr:yield(session_id, "call_master", RPC_CALL_TIMEOUT)
end

--通知其他线程
hive.send_worker = function(name, rpc, ...)
    hive.call(name, lencode(0, FLAG_REQ, WTITLE, rpc, ...))
end
