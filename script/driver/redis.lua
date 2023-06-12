--redis.lua
local Socket       = import("driver/socket.lua")
local QueueFIFO    = import("container/queue_fifo.lua")

local tonumber     = tonumber
local log_err      = logger.err
local log_info     = logger.info
local ssub         = string.sub
local slower       = string.lower
local sformat      = string.format
local tinsert      = table.insert
local is_array     = table_ext.is_array
local tjoin        = table_ext.join
local hhash        = hive.hash

local timer_mgr    = hive.get("timer_mgr")
local thread_mgr   = hive.get("thread_mgr")
local update_mgr   = hive.get("update_mgr")

local LineTitle    = "\r\n"
local SECOND_MS    = hive.enum("PeriodTime", "SECOND_MS")
local SECOND_10_MS = hive.enum("PeriodTime", "SECOND_10_MS")
local DB_TIMEOUT   = hive.enum("NetwkTime", "DB_CALL_TIMEOUT")
local POOL_COUNT   = environ.number("HIVE_DB_POOL_COUNT", 10)

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

local function _parse_packet(packet, istext)
    local line = _next_line(packet)
    if not line then
        return false, "packet isn't complete"
    end
    if istext then
        return true, true, line
    end
    local prefix, body = ssub(line, 1, 1), ssub(line, 2)
    local prefix_func  = _redis_proto_parser[prefix]
    if prefix_func then
        return prefix_func(body, packet)
    end
    return false, "packet format err"
end

_redis_proto_parser["$"] = function(body, packet)
    -- bulk string
    if tonumber(body) < 0 then
        return true, true
    end
    return _parse_packet(packet, true)
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
    keys             = { cmd = "KEYS" },
    type             = { cmd = "TYPE" },
    incr             = { cmd = "INCR" },
    incrby           = { cmd = "INCRBY", },
    rename           = { cmd = "RENAME" },
    ttl              = { cmd = "TTL" },
    dbsize           = { cmd = "DBSIZE" },
    pttl             = { cmd = "PTTL" }, -- >= 2.6
    setex            = { cmd = "SETEX" }, -- >= 2.0
    psetex           = { cmd = "PSETEX" }, -- >= 2.6
    get              = { cmd = "GET" },
    mget             = { cmd = "MGET" },
    getset           = { cmd = "GETSET" },
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
    hdel             = { cmd = "HDEL" }, -- >= 2.0
    hlen             = { cmd = "HLEN" }, -- >= 2.0
    hkeys            = { cmd = "HKEYS" }, -- >= 2.0
    hvals            = { cmd = "HVALS" }, -- >= 2.0
    hincrby          = { cmd = "HINCRBY" }, -- >= 2.0
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
}

local RedisDB        = class()
local prop           = property(RedisDB)
prop:reader("id", nil)              --id
prop:reader("passwd", nil)          --passwd
prop:reader("executer", nil)        --执行者
prop:reader("timer_id", nil)        --timer_id
prop:reader("connections", {})      --connections

function RedisDB:__init(conf, id)
    self.id     = id
    self.passwd = conf.passwd
    self:choose_host(conf.hosts)
    --attach_hour
    update_mgr:attach_hour(self)
    --setup
    self:setup()
end

function RedisDB:__release()
    self:close()
end

function RedisDB:set_executer(id)
    local index   = hhash(id, POOL_COUNT)
    self.executer = self.connections[index]
end

function RedisDB:choose_host(hosts)
    if not next(hosts) then
        log_err("[RedisDB][choose_host] redis config err: hosts is empty")
        return
    end
    local count = POOL_COUNT
    while count > 0 do
        for ip, port in pairs(hosts) do
            local socket            = Socket(self, ip, port)
            socket.task_queue       = QueueFIFO()
            self.connections[count] = socket
            count                   = count - 1
        end
    end
end

function RedisDB:set_options(opts)
end

function RedisDB:setup()
    for cmd, param in pairs(redis_commands) do
        RedisDB[cmd] = function(this, ...)
            return this:commit(param, ...)
        end
    end
    thread_mgr:entry(self:address(), function()
        self:check_alive()
    end)
end

function RedisDB:close()
    for _, sock in pairs(self.connections) do
        sock:close()
    end
    if self.timer_id then
        timer_mgr:unregister(self.timer_id)
        self.timer_id = nil
    end
end

function RedisDB:on_hour()
    for _, sock in pairs(self.connections) do
        if not sock:is_alive() then
            self.executer = sock
            self:commit({ cmd = "PING" })
        end
    end
end

function RedisDB:check_alive()
    if self.timer_id then
        timer_mgr:unregister(self.timer_id)
    end
    local ok = true
    for no, sock in pairs(self.connections) do
        if not sock:is_alive() then
            if not self:login(sock, no) then
                ok = false
            end
        end
    end
    self.timer_id = timer_mgr:once(ok and SECOND_10_MS or SECOND_MS, function()
        self:check_alive()
    end)
end

function RedisDB:login(socket, no)
    local ip, port = socket.ip, socket.port
    if not socket:connect(ip, port) then
        log_err("[RedisDB][login] connect db(%s:%s:%s) failed!", ip, port, no)
        return false
    end
    self.executer = socket
    if self.passwd and #self.passwd > 1 then
        self.executer = socket
        local ok, res = self:auth()
        if not ok or res ~= "OK" then
            log_err("[RedisDB][login] auth db(%s:%s:%s) auth failed! because: %s", ip, port, no, res)
            socket:close()
            return false
        end
    end
    log_info("[RedisDB][login] login db(%s:%s:%s) success!", ip, port, no)
    return true
end

function RedisDB:auth()
    return self:commit({ cmd = "AUTH" }, self.passwd)
end

function RedisDB:on_socket_error(sock, token, err)
    local task_queue = sock.task_queue
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
        local session_id = sock.task_queue:pop()
        if session_id then
            thread_mgr:response(session_id, rdsucc, res)
        end
    end
end

function RedisDB:wait_response(session_id, packet, param)
    local socket = self.executer
    if not socket then
        return false, "db not connected"
    end
    if not socket:send(packet) then
        return false, "send request failed"
    end
    socket.task_queue:push(session_id)
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

function RedisDB:commit(param, ...)
    local session_id = thread_mgr:build_session_id()
    local packet     = _compose_args(param.cmd, ...)
    return self:wait_response(session_id, packet, param)
end

function RedisDB:execute(cmd, ...)
    local lcmd = slower(cmd)
    if RedisDB[lcmd] then
        return self[lcmd](self, ...)
    end
    return self:commit({ cmd = cmd }, ...)
end

return RedisDB
