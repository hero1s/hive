--_listener.lua
local xpcall    = xpcall
local ipairs    = ipairs
local tpack     = table.pack
local tunpack   = table.unpack
local tremove   = table.remove
local log_err   = logger.err
local log_warn  = logger.warn
local dtraceback= debug.traceback

local Listener = class()
function Listener:__init()
    self._triggers = {}     -- map<event, {{listener, func_name}, ...}
    self._listeners = {}    -- map<event, listener>
    self._commands = {}     -- map<cmd, listener>
    self._ignores = {}       -- map<cmd, listener>
end

function Listener:add_trigger(trigger, event, handler)
    local func_name = handler or event
    local callback_func = trigger[func_name]
    if not callback_func or type(callback_func) ~= "function" then
        log_warn("[Listener][add_trigger] event(%s) handler is nil!", event)
        return
    end
    local info = { trigger, func_name }
    local triggers = self._triggers[event]
    if not triggers then
        self._triggers[event] = { info }
        return
    end
    triggers[#triggers + 1] = info
end

function Listener:remove_trigger(trigger, event)
    local trigger_array = self._triggers[event]
    if trigger_array then
        for i, context in pairs(trigger_array or {}) do
            if context[1] == trigger then
                tremove(trigger_array, i)
            end
        end
    end
end

function Listener:add_listener(listener, event, handler)
    if self._listeners[event] then
        log_warn("[Listener][add_listener] event(%s) repeat!", event)
        return
    end
    local func_name = handler or event
    local callback_func = listener[func_name]
    if not callback_func or type(callback_func) ~= "function" then
        log_warn("[Listener][add_listener] event(%s) callback is nil!", event)
        return
    end
    self._listeners[event] = { listener, func_name }
end

function Listener:remove_listener(event)
    self._listeners[event] = nil
end

function Listener:add_cmd_listener(listener, cmd, handler)
    if self._commands[cmd] then
        log_warn("[Listener][add_cmd_listener] cmd(%s) repeat!", cmd)
        return
    end
    local func_name = handler
    local callback_func = listener[func_name]
    if not callback_func or type(callback_func) ~= "function" then
        log_warn("[Listener][add_cmd_listener] cmd(%s) handler is nil!", cmd)
        return
    end
    self._commands[cmd] = { listener, func_name }
end

function Listener:remove_cmd_listener(cmd)
    self._commands[cmd] = nil
end

function Listener:notify_trigger(event, ...)
    for _, trigger_ctx in ipairs(self._triggers[event] or {}) do
        local trigger, func_name = tunpack(trigger_ctx)
        local callback_func = trigger[func_name]
        local ok, ret = xpcall(callback_func, dtraceback, trigger, ...)
        if not ok then
            log_err("[Listener][notify_listener] xpcall [%s:%s] failed: %s!", trigger:source(), func_name, ret)
        end
    end
end

function Listener:notify_listener(event, ...)
    local listener_ctx = self._listeners[event]
    if not listener_ctx then
        if not self._ignores[event] then
            log_warn("[Listener][notify_listener] event %s handler is nil!", event)
            self._ignores[event] = true
        end
        return tpack(false, "event handler is nil")
    end
    local listener, func_name = tunpack(listener_ctx)
    local callback_func = listener[func_name]
    local result = tpack(xpcall(callback_func, dtraceback, listener, ...))
    if not result[1] then
        log_err("[Listener][notify_listener] xpcall [%s:%s] failed: %s", listener:source(), func_name, result[2])
    end
    return result
end

function Listener:notify_command(cmd, ...)
    local listener_ctx = self._commands[cmd]
    if not listener_ctx then
        if not self._ignores[cmd] then
            log_warn("[Listener][notify_command] command %s handler is nil!", cmd)
            self._ignores[cmd] = true
        end
        return tpack(false, "command handler is nil")
    end
    --执行事件
    local listener, func_name = tunpack(listener_ctx)
    local callback_func = listener[func_name]
    local result = tpack(xpcall(callback_func, dtraceback, listener, ...))
    if not result[1] then
        log_err("[Listener][notify_command] xpcall [%s:%s] failed: %s!", listener:source(), func_name, result[2])
    end
    return result
end

--创建全局监听器
hive.event_mgr = Listener()

return Listener
