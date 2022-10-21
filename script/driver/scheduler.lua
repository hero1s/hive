--scheduler.lua
local lworker       = require("lworker")
local lcodec        = require("lcodec")

local pcall         = pcall
local log_err       = logger.err
local tpack         = table.pack
local tunpack       = table.unpack

local lencode       = lcodec.encode_slice
local ldecode       = lcodec.decode_slice

local RPC_TIMEOUT   = hive.enum("NetwkTime", "RPC_CALL_TIMEOUT")

local update_mgr    = hive.get("update_mgr")
local thread_mgr    = hive.get("thread_mgr")

local Scheduler = singleton()
function Scheduler:__init()
    update_mgr:attach_frame(self)
end

function Scheduler:on_frame()
    lworker.update()
end

function Scheduler:suspend(timeout)
    return lworker.suspend(timeout)
end

function Scheduler:setup(service)
    lworker.setup(service, environ.get("HIVE_SANDBOX"))
end

function Scheduler:startup(name, entry)
    local ok, err = pcall(lworker.startup, name, entry)
    if not ok then
        log_err("[Scheduler][startup] startup failed: %s", err)
    end
    return ok
end

--访问其他线程任务
function Scheduler:call(name, rpc, ...)
    local session_id = thread_mgr:build_session_id()
    lworker.call(name, lencode(session_id, rpc, ...))
    return thread_mgr:yield(session_id, "worker_call", RPC_TIMEOUT)
end

--访问其他线程任务
function Scheduler:send(name, rpc, ...)
    lworker.call(name, lencode(0, rpc, ...))
end

function hive.on_scheduler(slice)
    local rpc_res = tpack(pcall(ldecode, slice))
    if not rpc_res[1] then
        log_err("[Scheduler][on_scheduler] decode failed %s!", rpc_res[2])
        return
    end
    thread_mgr:response(tunpack(rpc_res, 2))
end

hive.scheduler = Scheduler()

return Scheduler
