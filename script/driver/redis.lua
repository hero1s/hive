--redis.lua
local Socket     = import("driver/socket.lua")
local QueueFIFO  = import("container/queue_fifo.lua")

local tonumber   = tonumber
local log_err    = logger.err
local log_info   = logger.info
local ssub       = string.sub
local sgsub      = string.gsub
local supper     = string.upper
local sformat    = string.format
local tpack      = table.pack

local event_mgr  = hive.get("event_mgr")
local update_mgr = hive.get("update_mgr")
local thread_mgr = hive.get("thread_mgr")
local timer_mgr  = hive.get("timer_mgr")

local LineTitle  = "\r\n"
local DB_TIMEOUT = hive.enum("NetwkTime", "DB_CALL_TIMEOUT")

local function _async_call(context, quote)
    local session_id = thread_mgr:build_session_id()
    if not context.commit_id then
        context.commit_id = session_id
    end
    context.session_id = session_id
    local fquote       = sformat("%s:%s", context.name, quote)
    return thread_mgr:yield(session_id, fquote, DB_TIMEOUT)
end

local _redis_resp_parser      = {
    ["+"] = function(context, body)
        --simple string
        return true, body
    end,
    ["-"] = function(context, body)
        -- error reply
        return false, body
    end,
    [":"] = function(context, body)
        -- integer reply
        return true, tonumber(body)
    end,
    ["$"] = function(context, body)
        -- bulk string
        if tonumber(body) < 0 then
            return true
        end
        return _async_call(context, "redis parse bulk string")
    end,
    ["*"] = function(context, body)
        -- array
        local length = tonumber(body)
        if length < 0 then
            return true
        end
        local array = {}
        local noerr = true
        for i = 1, length do
            local ok, value, session_id = _async_call(context, "redis parse array")
            if not ok then
                if session_id then
                    return ok, value, session_id
                end
                noerr = false
            end
            array[i] = value
        end
        return noerr, array
    end
}

local _redis_subscribe_replys = {
    message      = function(self, channel, data)
        log_info("[RedisDB][_redis_subscribe_replys] subscribe message channel(%s) data: %s", channel, data)
        event_mgr:notify_trigger("on_redis_subscribe", channel, data)
    end,
    pmessage     = function(self, channel, data, date2)
        log_info("[RedisDB][_redis_subscribe_replys] psubscribe pmessage channel(%s) data: %s, data2: %s", channel, data, date2)
        event_mgr:notify_trigger("on_redis_psubscribe", channel, data, date2)
    end,
    subscribe    = function(self, channel, status)
        log_info("[RedisDB][_redis_subscribe_replys] subscribe redis channel(%s) status: %s", channel, status)
        self.subscribes[channel] = true
    end,
    psubscribe   = function(self, channel, status)
        log_info("[RedisDB][_redis_subscribe_replys] psubscribe redis channel(%s) status: %s", channel, status)
        self.psubscribes[channel] = true
    end,
    unsubscribe  = function(self, channel, status)
        log_info("[RedisDB][_redis_subscribe_replys] unsubscribe redis channel(%s) status: %s", channel, status)
        self.subscribes[channel] = nil
    end,
    punsubscribe = function(self, channel, status)
        log_info("[RedisDB][_redis_subscribe_replys] punsubscribe redis channel(%s) status: %s", channel, status)
        self.psubscribes[channel] = nil
    end
}

local function _compose_bulk_string(value)
    if not value then
        return "\r\n$-1"
    end
    if type(value) ~= "string" then
        value = tostring(value)
    end
    return sformat("\r\n$%d\r\n%s", #value, value)
end

local function _compose_array(cmd, array)
    local count = 0
    if array then
        count = (array.n or #array)
    end
    local buff = sformat("*%d%s", count + 1, _compose_bulk_string(cmd))
    if count > 0 then
        for i = 1, count do
            buff = sformat("%s%s", buff, _compose_bulk_string(array[i]))
        end
    end
    return sformat("%s\r\n", buff)
end

local function _compose_message(cmd, msg)
    if not msg then
        return _compose_array(cmd)
    end
    if type(msg) == "table" then
        return _compose_array(cmd, msg)
    end
    return _compose_array(cmd, { msg })
end

local function _tokeys(value)
    if type(value) == 'string' then
        -- backwards compatibility path for Redis < 2.0
        local keys = {}
        sgsub(value, '[^%s]+', function(key)
            keys[#keys + 1] = key
        end)
        return keys
    end
    return value
end

local function _tomap(value)
    if (type(value) == 'table') then
        local new_value = { }
        for i = 1, #value, 2 do
            new_value[value[i]] = value[i + 1]
        end
        return new_value
    end
    return value
end

local function _toboolean(value)
    value = tostring(value)
    if value == '1' or value == 'true' or value == 'TRUE' then
        return true
    elseif value == '0' or value == 'false' or value == 'FALSE' then
        return false
    end
    return value
end

local subscribe_commands = {
    subscribe    = { cmd = "SUBSCRIBE" }, -- >= 2.0
    unsubscribe  = { cmd = "UNSUBSCRIBE" }, -- >= 2.0
    psubscribe   = { cmd = "PSUBSCRIBE" }, -- >= 2.0
    punsubscribe = { cmd = "PUNSUBSCRIBE" }, -- >= 2.0
}

local redis_commands     = {
    del              = { cmd = "DEL" },
    set              = { cmd = "SET" },
    type             = { cmd = "TYPE" },
    rename           = { cmd = "RENAME" },
    ttl              = { cmd = "TTL" },
    dbsize           = { cmd = "DBSIZE" },
    pttl             = { cmd = "PTTL" }, -- >= 2.6
    setex            = { cmd = "SETEX" }, -- >= 2.0
    psetex           = { cmd = "PSETEX" }, -- >= 2.6
    get              = { cmd = "GET" },
    mget             = { cmd = "MGET" },
    getset           = { cmd = "GETSET" },
    incr             = { cmd = "INCR" },
    incrby           = { cmd = "INCRBY" },
    decr             = { cmd = "DECR" },
    decrby           = { cmd = "DECRBY" },
    append           = { cmd = "APPEND" }, -- >= 2.0
    substr           = { cmd = "SUBSTR" }, -- >= 2.0
    strlen           = { cmd = "STRLEN" }, -- >= 2.2
    setrange         = { cmd = "SETRANGE" }, -- >= 2.2
    getrange         = { cmd = "GETRANGE" }, -- >= 2.2
    setbit           = { cmd = "SETBIT" }, -- >= 2.2
    getbit           = { cmd = "GETBIT" }, -- >= 2.2
    bitop            = { cmd = "BITOP" }, -- >= 2.6
    bitcount         = { cmd = "BITCOUNT" }, -- >= 2.6
    rpush            = { cmd = "RPUSH" },
    lpush            = { cmd = "LPUSH" },
    llen             = { cmd = "LLEN" },
    lrange           = { cmd = "LRANGE" },
    ltrim            = { cmd = "LTRIM" },
    lindex           = { cmd = "LINDEX" },
    lset             = { cmd = "LSET" },
    lrem             = { cmd = "LREM" },
    lpop             = { cmd = "LPOP" },
    rpop             = { cmd = "RPOP" },
    blpop            = { cmd = "BLPOP" }, -- >= 2.0
    brpop            = { cmd = "BRPOP" }, -- >= 2.0
    rpushx           = { cmd = "RPUSHX" }, -- >= 2.2
    lpushx           = { cmd = "LPUSHX" }, -- >= 2.2
    linsert          = { cmd = "LINSERT" }, -- >= 2.2
    sadd             = { cmd = "SADD" },
    srem             = { cmd = "SREM" },
    spop             = { cmd = "SPOP" },
    scard            = { cmd = "SCARD" },
    sinter           = { cmd = "SINTER" },
    sunion           = { cmd = "SUNION" },
    sdiff            = { cmd = "SDIFF" },
    zadd             = { cmd = "ZADD" },
    zrem             = { cmd = "ZREM" },
    zcount           = { cmd = "ZCOUNT" },
    zcard            = { cmd = "ZCARD" },
    zscore           = { cmd = "ZSCORE" },
    zrank            = { cmd = "ZRANK" }, -- >= 2.0
    zrevrank         = { cmd = "ZREVRANK" }, -- >= 2.0
    hget             = { cmd = "HGET" }, -- >= 2.0
    hincrby          = { cmd = "HINCRBY" }, -- >= 2.0
    hdel             = { cmd = "HDEL" }, -- >= 2.0
    hlen             = { cmd = "HLEN" }, -- >= 2.0
    hkeys            = { cmd = "HKEYS" }, -- >= 2.0
    hvals            = { cmd = "HVALS" }, -- >= 2.0
    echo             = { cmd = "ECHO" },
    select           = { cmd = "SELECT" },
    multi            = { cmd = "MULTI" }, -- >= 2.0
    exec             = { cmd = "EXEC" }, -- >= 2.0
    discard          = { cmd = "DISCARD" }, -- >= 2.0
    watch            = { cmd = "WATCH" }, -- >= 2.2
    unwatch          = { cmd = "UNWATCH" }, -- >= 2.2
    eval             = { cmd = "EVAL" }, -- >= 2.6
    evalsha          = { cmd = "EVALSHA" }, -- >= 2.6
    script           = { cmd = "SCRIPT" }, -- >= 2.6
    time             = { cmd = "TIME" }, -- >= 2.6
    client           = { cmd = "CLIENT" }, -- >= 2.4
    slaveof          = { cmd = "SLAVEOF" },
    save             = { cmd = "SAVE" },
    bgsave           = { cmd = "BGSAVE" },
    lastsave         = { cmd = "LASTSAVE" },
    flushdb          = { cmd = "FLUSHDB" },
    flushall         = { cmd = "FLUSHALL" },
    monitor          = { cmd = "MONITOR" },
    hmset            = { cmd = "HMSET" }, -- >= 2.0
    hmget            = { cmd = "HMGET" }, -- >= 2.0
    hscan            = { cmd = "HSCAN" }, -- >= 2.8
    sort             = { cmd = "SORT" },
    scan             = { cmd = "SCAN" }, -- >= 2.8
    mset             = { cmd = "MSET" },
    sscan            = { cmd = "SSCAN" }, -- >= 2.8
    publish          = { cmd = "PUBLISH" }, -- >= 2.0
    sinterstore      = { cmd = "SINTERSTORE" },
    sunionstore      = { cmd = "SUNIONSTORE" },
    sdiffstore       = { cmd = "SDIFFSTORE" },
    smembers         = { cmd = "SMEMBERS" },
    srandmember      = { cmd = "SRANDMEMBER" },
    rpoplpush        = { cmd = "RPOPLPUSH" },
    randomkey        = { cmd = "RANDOMKEY" },
    brpoplpush       = { cmd = "BRPOPLPUSH" }, -- >= 2.2
    bgrewriteaof     = { cmd = "BGREWRITEAOF" },
    zscan            = { cmd = "ZSCAN" }, -- >= 2.8
    zrange           = { cmd = "ZRANGE", },
    zrevrange        = { cmd = "ZREVRANGE" },
    zrangebyscore    = { cmd = "ZRANGEBYSCORE" },
    zrevrangebyscore = { cmd = "ZREVRANGEBYSCORE" }, -- >= 2.2
    zunionstore      = { cmd = "ZUNIONSTORE" }, -- >= 2.0
    zinterstore      = { cmd = "ZINTERSTORE" }, -- >= 2.0
    zremrangebyscore = { cmd = "ZREMRANGEBYSCORE" },
    zremrangebyrank  = { cmd = "ZREMRANGEBYRANK" }, -- >= 2.0
    zincrby          = { cmd = "ZINCRBY", convertor = tonumber },
    incrbyfloat      = { cmd = "INCRBYFLOAT", convertor = tonumber },
    hincrbyfloat     = { cmd = "HINCRBYFLOAT", convertor = tonumber }, -- >= 2.6
    setnx            = { cmd = "SETNX", convertor = _toboolean },
    exists           = { cmd = "EXISTS", convertor = _toboolean },
    renamenx         = { cmd = "RENAMENX", convertor = _toboolean },
    expire           = { cmd = "EXPIRE", convertor = _toboolean },
    pexpire          = { cmd = "PEXPIRE", convertor = _toboolean }, -- >= 2.6
    expireat         = { cmd = "EXPIREAT", convertor = _toboolean },
    pexpireat        = { cmd = "PEXPIREAT", convertor = _toboolean }, -- >= 2.6
    move             = { cmd = "MOVE", convertor = _toboolean },
    persist          = { cmd = "PERSIST", convertor = _toboolean }, -- >= 2.2
    smove            = { cmd = "SMOVE", convertor = _toboolean },
    sismember        = { cmd = "SISMEMBER", convertor = _toboolean },
    hset             = { cmd = "HSET", convertor = _toboolean }, -- >= 2.0
    hsetnx           = { cmd = "HSETNX", convertor = _toboolean }, -- >= 2.0
    hexists          = { cmd = "HEXISTS", convertor = _toboolean }, -- >= 2.0
    msetnx           = { cmd = "MSETNX", convertor = _toboolean },
    hgetall          = { cmd = "HGETALL", convertor = _tomap }, -- >= 2.0
    config           = { cmd = "CONFIG", convertor = _tomap }, -- >= 2.0
    keys             = { cmd = "KEYS", convertor = _tokeys },
}

local RedisDB            = class()
local prop               = property(RedisDB)
prop:reader("ip", nil)          --redis地址
prop:reader("index", 0)         --db index
prop:reader("port", 6379)       --redis端口
prop:reader("passwd", nil)      --passwd
prop:reader("subscribes", {})           --subscribes
prop:reader("psubscribes", {})          --psubscribes
prop:reader("command_sock", nil)        --网络连接对象
prop:reader("subscribe_sock", nil)      --网络连接对象
prop:reader("command_sessions", nil)    --command_sessions
prop:reader("subscribe_sessions", nil)  --subscribe_sessions
prop:reader("subscribe_context", nil)  --subscribe_sessions

function RedisDB:__init(conf)
    self.index              = conf.index
    self.passwd             = conf.passwd
    self.command_sock       = Socket(self)
    self.subscribe_sock     = Socket(self)
    self.command_sessions   = QueueFIFO()
    self.subscribe_sessions = QueueFIFO()
    self.subscribe_context  = { name = "subcribe_monitor" }
    self:choose_host(conf.hosts)
    self:set_options(conf.opts)
    --update
    update_mgr:attach_second(self)
    --setup
    self:setup()
end

function RedisDB:__release()
    self:close()
    timer_mgr:unregister(self.timer_id)
end

function RedisDB:setup()
    for cmd, param in pairs(redis_commands) do
        RedisDB[cmd] = function(this, ...)
            return this:commit(this.command_sock, param, ...)
        end
    end
    for cmd, param in pairs(subscribe_commands) do
        RedisDB[cmd] = function(this, ...)
            return this:commit(this.subscribe_sock, param, ...)
        end
    end
    self.timer_id = timer_mgr:loop(10 * 1000, function()
        self:ping()
    end)
end

function RedisDB:close()
    if self.command_sock then
        self:clear_session(self.command_sock, "action-close")
        self.command_sock:close()
    end
    if self.subscribe_sock then
        self:clear_session(self.subscribe_sock, "action-close")
        self.subscribe_sock:close()
    end
end

function RedisDB:choose_host(hosts)
    for host, port in pairs(hosts) do
        self.ip, self.port = host, port
        break
    end
end

function RedisDB:set_options(opts)

end

function RedisDB:login(socket, title)
    if not socket:connect(self.ip, self.port) then
        log_err("[MysqlDB][login] connect %s db(%s:%s) failed!", title, self.ip, self.port)
        return false
    end
    if self.passwd and self.passwd:len() > 1 then
        local ok, res = self:auth(socket)
        if not ok or res ~= "OK" then
            log_err("[RedisDB][login] auth %s db(%s:%s) failed! because: %s", title, self.ip, self.port, res)
            return false
        end
    end
    if self.index then
        local ok, res = self:select(self.index)
        if not ok or res ~= "OK" then
            log_err("[RedisDB][login] select %s db(%s:%s-%s) failed! because: %s", title, self.ip, self.port, self.index, res)
            return false
        end
    end
    log_info("[RedisDB][login] login %s db(%s:%s-%s) success!", title, self.ip, self.port, self.index)
    return true
end

function RedisDB:on_second()
    local _lock<close> = thread_mgr:lock("redis-second", true)
    if not _lock then
        return
    end
    local command_sock   = self.command_sock
    local subscribe_sock = self.subscribe_sock
    if not command_sock:is_alive() then
        self:login(command_sock, "query")
    end
    if not subscribe_sock:is_alive() then
        if self:login(subscribe_sock, "subcribe") then
            for channel in pairs(self.subscribes) do
                self:subscribe(channel)
            end
            for channel in pairs(self.psubscribes) do
                self:psubscribes(channel)
            end
        end
    end
end

function RedisDB:ping()
    self:commit(self.command_sock, { cmd = "PING" })
    self:commit(self.subscribe_sock, { cmd = "PING" })
end

function RedisDB:clear_session(sock, err)
    if sock == self.command_sock then
        for _, context in self.command_sessions:iter() do
            thread_mgr:response(context.session_id, false, err)
        end
        self.command_sessions:clear()
    else
        for _, context in self.subscribe_sessions:iter() do
            thread_mgr:response(context.session_id, false, err)
        end
        self.subscribe_sessions:clear()
    end
end

function RedisDB:on_socket_error(sock, token, err)
    self:clear_session(sock, err)
    log_err("[RedisDB][on_socket_error] token:%s, error:%s", token, err)
end

function RedisDB:on_socket_recv(sock, token)
    while true do
        local line, length = sock:peek_data(LineTitle)
        if not line then
            break
        end
        sock:pop(length)
        local context, cur_sessions = self:find_context(sock)
        if context and cur_sessions then
            thread_mgr:fork(function()
                local ok, res, cb_session_id = true, line, nil
                local session_id             = context.session_id
                local prefix, body           = ssub(line, 1, 1), ssub(line, 2)
                local prefix_func            = _redis_resp_parser[prefix]
                if prefix_func then
                    ok, res, cb_session_id = prefix_func(context, body)
                end
                if ok and sock == self.subscribe_sock then
                    self:on_subcribe_reply(res)
                end
                if session_id then
                    if session_id == context.commit_id then
                        if not cb_session_id then
                            cur_sessions:pop()
                        end
                    end
                    thread_mgr:response(session_id, ok, res)
                end
            end)
        end
    end
end

function RedisDB:on_subcribe_reply(res)
    if type(res) == "table" then
        local ttype, channel, data, data2 = res[1], res[2], res[3], res[4]
        local reply_func                  = _redis_subscribe_replys[ttype]
        if reply_func then
            reply_func(self, channel, data, data2)
        end
    end
end

function RedisDB:find_context(sock)
    local cur_sessions = (sock == self.command_sock) and self.command_sessions or self.subscribe_sessions
    local context      = cur_sessions:head()
    if context then
        return context, cur_sessions
    end
    if sock == self.subscribe_sock then
        return self.subscribe_context, cur_sessions
    end
end

function RedisDB:commit(sock, param, ...)
    if not sock then
        return false, "sock isn't connected"
    end
    local packet = _compose_message(param.cmd, tpack(...))
    if not sock:send(packet) then
        return false, "send request failed"
    end
    local context      = { name = param.cmd }
    local cur_sessions = (sock == self.command_sock) and self.command_sessions or self.subscribe_sessions
    cur_sessions:push(context)
    local ok, res   = _async_call(context, "redis commit")
    local convertor = param.convertor
    if ok and convertor then
        return ok, convertor(res)
    end
    return ok, res
end

function RedisDB:execute(cmd, ...)
    if RedisDB[cmd] then
        return self[cmd](self, ...)
    end
    return self:commit(self.command_sock, { cmd = supper(cmd) }, ...)
end

function RedisDB:auth(socket)
    return self:commit(socket, { cmd = "AUTH" }, self.passwd)
end

return RedisDB
