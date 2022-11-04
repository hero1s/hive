--scheduler.lua
local lcodec      = require("lcodec")
local pcall       = pcall
local log_info    = logger.info
local log_err     = logger.err
local tpack       = table.pack
local tunpack     = table.unpack

local lencode     = lcodec.encode_slice
local ldecode     = lcodec.decode_slice

local RPC_TIMEOUT = hive.enum("NetwkTime", "RPC_CALL_TIMEOUT")

local update_mgr  = hive.get("update_mgr")
local thread_mgr  = hive.get("thread_mgr")

local Scheduler   = singleton()
local prop        = property(Scheduler)
prop:reader("services", {})          --全部服务

function Scheduler:__init()
    update_mgr:attach_frame(self)
    update_mgr:attach_quit(self)
end

function Scheduler:on_quit()
    self:stop()
end

function Scheduler:on_frame()
    hive.worker_update()
end

function Scheduler:suspend(timeout)
    return hive.worker_suspend(timeout)
end

function Scheduler:setup(service)
    hive.worker_setup(service, environ.get("HIVE_SANDBOX"))
end

function Scheduler:startup(name, entry)
    local ok, err = pcall(hive.worker_startup, name, entry)
    if not ok then
        log_err("[Scheduler][startup] startup failed: %s", err)
        return ok
    end
    self.services[name] = name
    log_info("[Scheduler][startup] startup %s: %s", name, entry)
    return ok
end

function Scheduler:stop(name)
    if name then
        self:call(name, "stop")
        self.services[name] = nil
    else
        for _, v in pairs(self.services) do
            self:call(v, "stop")
            self.services[v] = nil
        end
    end
end

--访问其他线程任务
function Scheduler:call(name, rpc, ...)
    local session_id = thread_mgr:build_session_id()
    hive.worker_call(name, lencode(session_id, rpc, ...))
    return thread_mgr:yield(session_id, "worker_call", RPC_TIMEOUT)
end

--访问其他线程任务
function Scheduler:send(name, rpc, ...)
    hive.worker_call(name, lencode(0, rpc, ...))
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
