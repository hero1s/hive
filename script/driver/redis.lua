--redis.lua
local Socket       = import("driver/socket.lua")
local QueueFIFO    = import("container/queue_fifo.lua")

local tonumber     = tonumber
local log_err      = logger.err
local log_info     = logger.info
local ssub         = string.sub
local sgsub        = string.gsub
local supper       = string.upper
local sformat      = string.format
local tinsert      = table.insert
local env_number   = environ.number
local is_array     = table_ext.is_array
local tjoin        = table_ext.join

local timer_mgr    = hive.get("timer_mgr")
local thread_mgr   = hive.get("thread_mgr")

local LineTitle    = "\r\n"
local SECOND_MS    = hive.enum("PeriodTime", "SECOND_MS")
local SECOND_10_MS = hive.enum("PeriodTime", "SECOND_10_MS")
local DB_TIMEOUT   = hive.enum("NetwkTime", "DB_CALL_TIMEOUT")

local function _next_line(resp)
    local nindex = resp.cur + 1
    local elem   = resp.elem[nindex]
    if elem then
        resp.cur = nindex
        return elem[1]
    end
end

local function _parse_offset(resp)
    return resp.elem[resp.cur][2]
end

local _redis_proto_parser = {}
_redis_proto_parser["+"]  = function(body)
    --simple string
    return true, true, body
end

_redis_proto_parser["-"]  = function(body)
    -- error reply
    return true, false, body
end

_redis_proto_parser[":"]  = function(body)
    -- integer reply
    return true, true, tonumber(body)
end

local function _parse_packet(packet)
    local line = _next_line(packet)
    if not line then
        return false, "packet isn't complete"
    end
    local prefix, body = ssub(line, 1, 1), ssub(line, 2)
    local prefix_func  = _redis_proto_parser[prefix]
    if prefix_func then
        return prefix_func(body, packet)
    end
    return true, true, line
end

_redis_proto_parser["$"] = function(body, packet)
    -- bulk string
    if tonumber(body) < 0 then
        return true, true
    end
    return _parse_packet(packet)
end

_redis_proto_parser["*"] = function(body, packet)
    -- array
    local length = tonumber(body)
    if length < 0 then
        return true, true
    end
    local array = {}
    for i = 1, length do
        local ok, err, value = _parse_packet(packet)
        if not ok then
            return false, err
        end
        array[i] = value
    end
    return true, true, array
end

local function _compose_bulk_string(value)
    if not value then
        return "\r\n$-1"
    end
    if type(value) ~= "string" then
        value = tostring(value)
    end
    return sformat("\r\n$%d\r\n%s", #value, value)
end

local function _format_args(...)
    local args = {}
    for _, arg in pairs({ ... }) do
        if type(arg) ~= "table" then
            tinsert(args, arg)
        else
            if is_array(arg) then
                tjoin(arg, args)
            else
                for key, value in pairs(arg) do
                    tinsert(args, key)
                    tinsert(args, value)
                end
            end
        end
    end
    return args
end

local function _compose_args(cmd, ...)
    local args = _format_args(...)
    local buff = sformat("*%d%s", #args + 1, _compose_bulk_string(cmd))
    for _, arg in ipairs(args) do
        buff = sformat("%s%s", buff, _compose_bulk_string(arg))
    end
    return sformat("%s\r\n", buff)
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
    return {}
end

local function _tomap(value)
    if (type(value) == 'table') then
        local maps = { }
        for i = 1, #value, 2 do
            maps[value[i]] = value[i + 1]
        end
        return maps
    end
    return {}
end

local function _toboolean(value)
    value = tostring(value)
    if value == '1' or value == 'true' or value == 'TRUE' then
        return true
    end
    return false
end

local redis_commands = {
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

local RedisDB        = class()
local prop           = property(RedisDB)
prop:reader("passwd", nil)              --passwd
prop:reader("drivers", {})              --drivers
prop:reader("timer_id", nil)            --next_time

function RedisDB:__init(conf)
    self.passwd = conf.passwd
    self:choose_host(conf.hosts)
    --setup
    self:setup()
end

function RedisDB:__release()
    self:close()
end

function RedisDB:choose_host(hosts)
    local pcount = env_number("HIVE_DB_POOL_COUNT", 1)
    while true do
        for ip, port in pairs(hosts) do
            local socket         = Socket(self, ip, port)
            socket.task_queue    = QueueFIFO()
            self.drivers[socket] = QueueFIFO()
            pcount               = pcount - 1
            if pcount == 0 then
                return
            end
        end
    end
end

function RedisDB:set_options(opts)
end

function RedisDB:setup()
    for cmd, param in pairs(redis_commands) do
        RedisDB[cmd] = function(this, ...)
            local socket = self:choose_driver()
            if not socket then
                return false, "redis not connested"
            end
            return this:commit(socket, param, ...)
        end
    end
    thread_mgr:entry(self:address(), function()
        self:check_alive()
    end)
end

function RedisDB:close()
    for sock in pairs(self.drivers) do
        sock:close()
    end
end

function RedisDB:login(socket, title)
    if not socket:connect(socket.ip, socket.port) then
        log_err("[MysqlDB][login] connect %s db(%s:%s) failed!", title, socket.ip, socket.port)
        return false
    end
    if self.passwd and self.passwd:len() > 1 then
        local ok, res = self:auth(socket)
        if not ok or res ~= "OK" then
            log_err("[RedisDB][login] auth %s db(%s:%s) failed! because: %s", title, socket.ip, socket.port, res)
            return false
        end
    end
    log_info("[RedisDB][login] login %s db(%s:%s:%s) success!", title, socket.ip, socket.port, socket.token)
    return true
end

function RedisDB:ping()
    for sock in pairs(self.drivers) do
        if not sock:is_alive() then
            self:commit(sock, { cmd = "PING" })
        end
    end
end

function RedisDB:check_alive()
    if self.timer_id then
        timer_mgr:unregister(self.timer_id)
    end
    local ok = true
    for sock in pairs(self.drivers) do
        if not sock:is_alive() then
            if not self:login(sock, "query") then
                ok = false
            end
        end
    end
    self.timer_id = timer_mgr:once(ok and SECOND_10_MS or SECOND_MS, function()
        self:check_alive()
    end)
end

function RedisDB:on_socket_error(sock, token, err)
    local task_queue = self.drivers[sock]
    local session_id = task_queue:pop()
    while session_id do
        thread_mgr:response(session_id, false, err)
        session_id = task_queue:pop()
    end
    --检查活跃
    thread_mgr:entry(self:address(), function()
        self:check_alive()
    end)
end

function RedisDB:on_socket_recv(sock, token)
    while true do
        local packet = sock:peek_lines(LineTitle)
        if not packet then
            break
        end
        local ok, succ, rdsucc, res = pcall(_parse_packet, packet)
        if not ok then
            log_err("[RedisDB][on_socket_recv] exec parse failed: %s", succ)
            break
        end
        if not succ then
            log_err("[RedisDB][on_socket_recv] parse failed: %s", rdsucc)
            break
        end
        sock:pop(_parse_offset(packet))
        local task_queue = self.drivers[sock]
        local session_id = task_queue:pop()
        if session_id then
            thread_mgr:response(session_id, rdsucc, res)
        end
    end
end

function RedisDB:wait_response(session_id, socket, packet, param)
    if not socket:send(packet) then
        return false, "send request failed"
    end
    local task_queue = self.drivers[socket]
    task_queue:push(session_id)
    local ok, res = thread_mgr:yield(session_id, sformat("redis_comit:%s", param.cmd), DB_TIMEOUT)
    if not ok then
        log_err("[RedisDB][wait_response] exec cmd %s failed: %s", param.cmd, res)
        return ok, res
    end
    local convertor = param.convertor
    if convertor then
        return ok, convertor(res)
    end
    return ok, res
end

function RedisDB:commit(socket, param, ...)
    local session_id = thread_mgr:build_session_id()
    local packet     = _compose_args(param.cmd, ...)
    return self:wait_response(session_id, socket, packet, param)
end

function RedisDB:execute(cmd, ...)
    if RedisDB[cmd] then
        return self[cmd](self, ...)
    end
    local socket = self:choose_driver()
    if not socket then
        return false, "redis not connested"
    end
    return self:commit(socket, { cmd = supper(cmd) }, ...)
end

function RedisDB:auth(socket)
    return self:commit(socket, { cmd = "AUTH" }, self.passwd)
end

function RedisDB:choose_driver()
    local socket
    local task_size = 0
    for driver, task_queue in pairs(self.drivers) do
        if driver:is_alive() then
            local tsize = task_queue:size()
            if not socket or tsize < task_size then
                task_size = tsize
                socket    = driver
            end
        end
    end
    return socket
end

return RedisDB
