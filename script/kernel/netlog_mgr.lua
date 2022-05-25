-- netlog_mgr.lua
local odate         = os.date
local qget          = hive.get
local qenum         = hive.enum
local log_debug     = logger.debug
local set_monitor   = logger.set_monitor
local sfind         = string.find
local sformat       = string.format
local ssplit        = string_ext.split

local event_mgr     = qget("event_mgr")
local timer_mgr     = qget("timer_mgr")
local thread_mgr    = qget("thread_mgr")

local SUCCESS       = qenum("KernCode", "SUCCESS")
local SECOND_MS     = qenum("PeriodTime", "SECOND_MS")
local SECOND_5_S    = qenum("PeriodTime", "SECOND_5_S")

local PULL_CNT_MAX  = 10

local NetlogMgr = singleton()
local prop = property(NetlogMgr)
prop:reader("sessions", {})
function NetlogMgr:__init()
    event_mgr:add_listener(self, "rpc_show_log")
    timer_mgr:loop(SECOND_MS, function()
        self:on_timer()
    end)
end

function NetlogMgr:open_session(data)
    local session_id = data.session_id
    if not session_id then
        session_id = thread_mgr:build_session_id()
    end
    local session = self.sessions[session_id]
    if not session then
        session = {
            pull_index  = 0,
            cache_logs  = {},
            filters     = {},
            session_id  = session_id,
        }
        self.sessions[session_id] = session
    end
    if data.filters then
        session.filters = ssplit(data.filters, " ")
    end
    session.active_time = hive.now
    return session
end

function NetlogMgr:close_session(session_id)
    self.sessions[session_id] = nil
    if not next(self.sessions) then
        set_monitor(nil)
    end
end

function NetlogMgr:notify(level, content)
    for _, session in pairs(self.sessions) do
        local cache = false
        if #session.filters == 0 then
            cache = true
            goto docache
        end
        for _, filter in pairs(session.filters) do
            if sfind(content, filter) then
                cache = true
                goto docache
            end
        end
        :: docache ::
        if cache then
            local cache_logs = session.cache_logs
            cache_logs[#cache_logs + 1] = sformat("[%s][%s]%s", odate("%Y-%m-%d %H:%M:%S"), level, content)
        end
    end
end

function NetlogMgr:rpc_show_log(data)
    if not next(self.sessions) then
        set_monitor(self)
    end
    local show_logs = {}
    local session = self:open_session(data)
    local log_size = #(session.cache_logs)
    local log_cnt = log_size - session.pull_index
    if log_cnt > 0 then
        local count = log_cnt > PULL_CNT_MAX and PULL_CNT_MAX or log_cnt
        for idx = 1, count do
            show_logs[#show_logs + 1] = session.cache_logs[session.pull_index + idx]
        end
        session.pull_index = session.pull_index + count
        if session.pull_index >= log_size then
            session.cache_logs = {}
            session.pull_index = 0
        end
    end
    return SUCCESS, { logs = show_logs, session_id = session.session_id }
end

function NetlogMgr:on_timer()
    local cur_time = hive.now
    for session_id, session in pairs(self.sessions) do
        if cur_time - session.active_time > SECOND_5_S then
            log_debug("[NetlogMgr][on_timer]->overdue->session_id:%s", session_id)
            self:close_session(session_id)
        end
    end
end

hive.Netllog_mgr = NetlogMgr()

return NetlogMgr
