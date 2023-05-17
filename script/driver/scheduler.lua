--scheduler.lua
local lcodec           = require("lcodec")
local pcall            = pcall
local log_info         = logger.info
local log_err          = logger.err
local tpack            = table.pack
local tunpack          = table.unpack

local lencode          = lcodec.encode_slice
local ldecode          = lcodec.decode_slice
local worker_call      = hive.worker_call
local worker_broadcast = hive.worker_broadcast
local worker_update    = hive.worker_update

local FLAG_REQ         = hive.enum("FlagMask", "REQ")
local FLAG_RES         = hive.enum("FlagMask", "RES")
local RPC_CALL_TIMEOUT = hive.enum("NetwkTime", "RPC_CALL_TIMEOUT")

local event_mgr        = hive.get("event_mgr")
local thread_mgr       = hive.get("thread_mgr")

local Scheduler        = singleton()

function Scheduler:__init()
    hive.worker_setup("hive")
end

function Scheduler:quit()
    hive.worker_shutdown()
end

function Scheduler:update()
    worker_update()
end

function Scheduler:startup(name, entry)
    local ok, err = pcall(hive.worker_startup, name, entry)
    if not ok then
        log_err("[Scheduler][startup] startup failed: %s", err)
        return ok
    end
    log_info("[Scheduler][startup] startup %s: %s", name, entry)
    return ok
end

--访问其他线程任务
function Scheduler:broadcast(rpc, ...)
    worker_broadcast(lencode(0, FLAG_REQ, "master", rpc, ...))
end

--访问其他线程任务
function Scheduler:call(name, rpc, ...)
    local session_id = thread_mgr:build_session_id()
    if worker_call(name, lencode(session_id, FLAG_REQ, "master", rpc, ...)) then
        return thread_mgr:yield(session_id, "worker_call", RPC_CALL_TIMEOUT)
    end
    return false, "call failed!"
end

--访问其他线程任务
function Scheduler:send(name, rpc, ...)
    worker_call(name, lencode(0, FLAG_REQ, "master", rpc, ...))
end

--事件分发
local function notify_rpc(session_id, title, rpc, ...)
    local rpc_datas = event_mgr:notify_listener(rpc, ...)
    if session_id > 0 then
        worker_call(title, lencode(session_id, FLAG_RES, tunpack(rpc_datas)))
    end
end

--事件分发
local function scheduler_rpc(session_id, flag, ...)
    if flag == FLAG_REQ then
        notify_rpc(session_id, ...)
    else
        thread_mgr:response(session_id, ...)
    end
end

function hive.on_scheduler(slice)
    local rpc_res = tpack(pcall(ldecode, slice))
    if not rpc_res[1] then
        log_err("[Scheduler][on_scheduler] decode failed %s!", rpc_res[2])
        return
    end
    thread_mgr:fork(function()
        scheduler_rpc(tunpack(rpc_res, 2))
    end)
end

hive.scheduler = Scheduler()

return Scheduler
