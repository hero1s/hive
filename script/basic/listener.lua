--_listener.lua
local xpcall     = xpcall
local ipairs     = ipairs
local select     = select
local tpack      = table.pack
local tunpack    = table.unpack
local tremove    = table.remove
local log_err    = logger.err
local log_warn   = logger.warn
local dtraceback = debug.traceback

local Listener   = class()
function Listener:__init()
    self._triggers  = {}     -- map<event, {{listener, func_name}, ...}
    self._votes     = {}     -- map<event, {{listener, func_name}, ...}
    self._listeners = {}     -- map<event, listener>
    self._commands  = {}     -- map<cmd, listener>
    self._ignores   = {}     -- map<cmd, bool>
    self.thread_mgr = nil
end

function Listener:add_trigger(trigger, event, handler)
    local func_name     = handler or event
    local callback_func = trigger[func_name]
    if not callback_func or type(callback_func) ~= "function" then
        log_err("[Listener][add_trigger] event({}) handler is nil!", event)
        return
    end
    local info     = { trigger, func_name }
    local triggers = self._triggers[event]
    if not triggers then
        self._triggers[event] = { info }
        return
    end
    triggers[#triggers + 1] = info
end

function Listener:remove_trigger(trigger, event)
    local remove_array = function(trigger_array)
        if trigger_array then
            for i = #trigger_array, 1, -1 do
                local context = trigger_array[i]
                if context[1] == trigger then
                    tremove(trigger_array, i)
                end
            end
        end
    end
    if event then
        remove_array(self._triggers[event])
    else
        for _, trigger_array in pairs(self._triggers or {}) do
            remove_array(trigger_array)
        end
    end
end

--支持队列处理
function Listener:add_listener(listener, event, handler, queue_param)
    if self._listeners[event] then
        log_err("[Listener][add_listener] event({}) repeat!", event)
        return
    end
    local func_name     = handler or event
    local callback_func = listener[func_name]
    if not callback_func or type(callback_func) ~= "function" then
        log_err("[Listener][add_listener] event({}) callback is nil!", event)
        return
    end
    self._listeners[event] = { listener, func_name, queue_param }
    if queue_param and not self.thread_mgr then
        self.thread_mgr = hive.get("thread_mgr")
    end
end

function Listener:remove_listener(event)
    self._listeners[event] = nil
end

function Listener:add_cmd_listener(listener, cmd, handler)
    if self._commands[cmd] then
        log_err("[Listener][add_cmd_listener] cmd({}) repeat!", cmd)
        return
    end
    local func_name     = handler
    local callback_func = listener[func_name]
    if not callback_func or type(callback_func) ~= "function" then
        log_err("[Listener][add_cmd_listener] cmd({}) handler is nil!", cmd)
        return
    end
    self._commands[cmd] = { listener, func_name }
end

function Listener:remove_cmd_listener(cmd)
    self._commands[cmd] = nil
end

function Listener:add_vote(trigger, event, handler)
    local func_name     = handler or event
    local callback_func = trigger[func_name]
    if not callback_func or type(callback_func) ~= "function" then
        log_err("[Listener][add_vote] event({}) handler is nil!", event)
        return
    end
    local info  = { trigger, func_name }
    local votes = self._votes[event]
    if not votes then
        self._votes[event] = { info }
        return
    end
    votes[#votes + 1] = info
end

function Listener:notify_trigger(event, ...)
    for _, trigger_ctx in ipairs(self._triggers[event] or {}) do
        local trigger, func_name = tunpack(trigger_ctx)
        local callback_func      = trigger[func_name]
        local ok, ret            = xpcall(callback_func, dtraceback, trigger, ...)
        if not ok then
            log_err("[Listener][notify_trigger] xpcall [{}:{}] failed: {}!,call from:{}", trigger:source(), func_name, ret, hive.where_call())
        end
    end
end

function Listener:notify_listener(event, ...)
    local listener_ctx = self._listeners[event]
    if not listener_ctx then
        if not self._ignores[event] then
            log_warn("[Listener][notify_listener] event {} handler is nil!,call from:{}", event, hive.where_call())
            self._ignores[event] = true
        end
        return tpack(false, "event handler is nil")
    end
    local listener, func_name, queue_param = tunpack(listener_ctx)
    local callback_func                    = listener[func_name]
    local result
    --队列派发
    if queue_param and type(queue_param) == "number" then
        if select('#', ...) < queue_param then
            log_err("[Listener][notify_listener] less param to queue lock,rpc:{},queue_param:{}", event, queue_param)
            result = tpack(xpcall(callback_func, dtraceback, listener, ...))
            goto exit
        end
        local qparam = select(queue_param, ...)
        if type(qparam) ~= "number" and type(qparam) ~= "string" then
            log_err("[Listener][notify_listener] error param for queue lock,rpc:{},queue_param:{}", event, qparam)
            result = tpack(xpcall(callback_func, dtraceback, listener, ...))
            goto exit
        end
        local _<close> = self.thread_mgr:lock("rpc_queue-" .. qparam)
        result         = tpack(xpcall(callback_func, dtraceback, listener, ...))
    else
        result = tpack(xpcall(callback_func, dtraceback, listener, ...))
    end
    :: exit ::
    if not result[1] then
        log_err("[Listener][notify_listener] xpcall [{}:{}] failed: {},call from:{}", listener:source(), func_name, result[2], hive.where_call())
    end
    return result
end

function Listener:notify_command(cmd, ...)
    local listener_ctx = self._commands[cmd]
    if not listener_ctx then
        if not self._ignores[cmd] then
            log_warn("[Listener][notify_command] command {} handler is nil!", cmd)
            self._ignores[cmd] = true
        end
        return tpack(false, "command handler is nil")
    end
    --执行事件
    local listener, func_name = tunpack(listener_ctx)
    local callback_func       = listener[func_name]
    local result              = tpack(xpcall(callback_func, dtraceback, listener, ...))
    if not result[1] then
        log_err("[Listener][notify_command] xpcall [{}:{}] failed: {}!,call from:{}", listener:source(), func_name, result[2], hive.where_call())
    end
    return result
end

function Listener:fire_vote(event, ...)
    for _, vote_ctx in ipairs(self._votes[event] or {}) do
        local voter, func_name = tunpack(vote_ctx)
        local callback_func    = voter[func_name]
        local ok, ret          = xpcall(callback_func, dtraceback, voter, ...)
        if not ok then
            log_err("[Listener][fire_vote] xpcall [{}:{}] failed: {}!,call from:{}", voter:source(), func_name, ret, hive.where_call())
        end
        if not ret then
            log_warn("[Listener][fire_vote] vote down:[{}]", voter:source())
            return false
        end
    end
    return true
end

--创建全局监听器
hive.event_mgr = Listener()

return Listener
