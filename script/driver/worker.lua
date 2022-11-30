--worker.lua
import("basic/basic.lua")
import("basic/json.lua")
import("kernel/config_mgr.lua")
local lcodec     = require("lcodec")
local ltimer     = require("ltimer")

local pcall      = pcall
local log_err    = logger.err
local tpack      = table.pack
local tunpack    = table.unpack
local raw_yield  = coroutine.yield
local raw_resume = coroutine.resume
local lencode    = lcodec.encode_slice
local ldecode    = lcodec.decode_slice
local ltime      = ltimer.time

local event_mgr  = hive.get("event_mgr")
local co_hookor  = hive.load("co_hookor")
local socket_mgr = hive.load("socket_mgr")
local update_mgr = hive.load("update_mgr")
local thread_mgr = hive.load("thread_mgr")

--初始化网络
local function init_network()
    local lbus      = require("luabus")
    local max_conn  = environ.number("HIVE_MAX_CONN", 4096)
    socket_mgr      = lbus.create_socket_mgr(max_conn)
    hive.socket_mgr = socket_mgr
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
    --import("kernel/perfeval_mgr.lua")
    --import("kernel/statis_mgr.lua")
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
    hive.update()
    --系统更新
    update_mgr:update(ltime())
end

--事件分发
local function worker_rpc(session_id, rpc, ...)
    if rpc == "stop" then
        hive.stop()
        return
    end
    local rpc_datas = event_mgr:notify_listener(rpc, ...)
    if session_id > 0 then
        hive.callback(lencode(session_id, tunpack(rpc_datas)))
    end
end

--rpc调用
hive.on_worker = function(slice)
    local rpc_res = tpack(pcall(ldecode, slice))
    if not rpc_res[1] then
        log_err("[hive][on_worker] decode failed %s!", rpc_res[2])
        return
    end
    thread_mgr:fork(function()
        worker_rpc(tunpack(rpc_res, 2))
    end)
end
