--redis.lua
local Socket       = import("driver/socket.lua")

local tonumber     = tonumber
local log_err      = logger.err
local log_info     = logger.info
local sformat      = string.format
local slower       = string.lower
local tinsert      = table.insert
local mrandom      = math_ext.random
local crc16        = crypt.crc16
local tdelete      = table_ext.delete
local qhash        = codec.hash_code
local makechan     = hive.make_channel
local jsoncodec    = json.jsoncodec
local rediscodec   = codec.rediscodec

local thread_mgr   = hive.get("thread_mgr")
local event_mgr    = hive.get("event_mgr")
local update_mgr   = hive.get("update_mgr")

local SUCCESS      = hive.enum("KernCode", "SUCCESS")
local SECOND_MS    = hive.enum("PeriodTime", "SECOND_MS")
local SECOND_10_MS = hive.enum("PeriodTime", "SECOND_10_MS")
local DB_TIMEOUT   = hive.enum("NetwkTime", "DB_CALL_TIMEOUT")
local POOL_COUNT   = environ.number("HIVE_DB_POOL_COUNT", 3)
local REDIS_SLOT   = 16384

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
    if value == 1 or value == 'true' or value == 'TRUE' then
        return true
    end
    return false
end

local function _toscan(value)
    if (type(value) == 'table') then
        return tonumber(value[1]), value[2]
    end
    return 0, {}
end

local function _tohscan(value)
    if (type(value) == 'table') then
        return tonumber(value[1]), _tomap(value[2])
    end
    return 0, {}
end

local rconvertors = {
    scan         = _toscan,
    sscan        = _toscan,
    hscan        = _tohscan,
    zscan        = _tohscan,
    zincrby      = tonumber,
    incrbyfloat  = tonumber,
    hincrbyfloat = tonumber,
    setnx        = _toboolean,
    exists       = _toboolean,
    renamenx     = _toboolean,
    expire       = _toboolean,
    pexpire      = _toboolean,
    expireat     = _toboolean,
    pexpireat    = _toboolean,
    move         = _toboolean,
    persist      = _toboolean,
    smove        = _toboolean,
    sismember    = _toboolean,
    hset         = _toboolean,
    hsetnx       = _toboolean,
    hexists      = _toboolean,
    msetnx       = _toboolean,
    hgetall      = _tomap,
    config       = _tomap,
}

local RedisDB     = class()
local prop        = property(RedisDB)
prop:reader("passwd", nil)          --passwd
prop:reader("jcodec", nil)          --jcodec
prop:reader("timer_id", nil)        --timer_id
prop:reader("connections", {})      --connections
prop:reader("clusters", {})         --clusters
prop:reader("alives", {})           --alives
prop:reader("slots", {})            --slots
prop:reader("req_counter", nil)
prop:reader("res_counter", nil)
prop:reader("subscrible", false)
prop:reader("cluster", false)       --cluster

function RedisDB:__init(conf)
    self.passwd = conf.passwd
    self:set_options(conf.opts)
    --attach_hour
    update_mgr:attach_hour(self)
    --codec
    self.jcodec = jsoncodec()
    --setup
    self:setup(conf)
end

function RedisDB:__release()
    self:close()
end

function RedisDB:close()
    for _, sock in pairs(self.alives) do
        sock:close()
    end
    for _, sock in pairs(self.connections) do
        sock:close()
    end
    self.timer:unregister()
    self.connections = {}
    self.alives      = {}
end

function RedisDB:setup(conf)
    self:setup_pool(conf.hosts)
    self.timer = hive.make_timer()
    self.timer:loop(SECOND_MS, function()
        self:check_alive()
    end)
    self.req_counter = hive.make_sampling(sformat("redis %s req", conf.db))
    self.res_counter = hive.make_sampling(sformat("redis %s res", conf.db))
end

function RedisDB:setup_pool(hosts)
    if not next(hosts) then
        log_err("[RedisDB][setup_pool] redis config err: hosts is empty")
        return
    end
    local count = 1
    for _, host in pairs(hosts) do
        for c = 1, POOL_COUNT do
            local socket            = Socket(self, host[1], host[2])
            self.connections[count] = socket
            socket:set_id(count)
            count = count + 1
        end
    end
end

function RedisDB:choose_node(key)
    if self.cluster and type(key) == "string" then
        local index = crc16(key) % REDIS_SLOT
        for _, cluster in pairs(self.clusters) do
            if index >= cluster.min and index <= cluster.max then
                local count = #cluster.alives
                if count > 0 then
                    return cluster.alives[(index % count) + 1]
                end
            end
        end
        return
    end
    local count = #self.alives
    if count > 0 then
        local index = qhash(key or mrandom(), count)
        return self.alives[index]
    end
end

function RedisDB:set_options(opts)
    if opts.cluster then
        log_info("[RedisDB][set_options] cluster status open")
        self.cluster = true
    end
end

function RedisDB:available()
    return #self.alives > 0
end

function RedisDB:on_hour()
    for _, sock in pairs(self.alives) do
        self:direct_send(sock, "PING")
    end
end

function RedisDB:check_clusters()
    if self.cluster then
        local _, socket = next(self.alives)
        if not socket then
            return
        end
        local ok, res = self:commit(socket, "cluster", "slots")
        if not ok then
            log_err("[RedisDB][check_clusters] load cluster slots failed! because: {}", res)
            return
        end
        for i, info in pairs(res) do
            for j = 3, #info do
                self.slots[info[j][2]] = i
            end
            self.clusters[i] = { min = info[1], max = info[2], alives = {} }
        end
        for _, sock in pairs(self.alives) do
            local index   = self.slots[sock.port] or 0
            local cluster = self.clusters[index]
            if cluster then
                tinsert(cluster.alives, sock)
            end
        end
    end
end

function RedisDB:check_alive()
    if next(self.connections) then
        thread_mgr:entry(self:address(), function()
            local channel = makechan("check redis")
            for _, sock in pairs(self.connections) do
                channel:push(function()
                    return self:login(sock)
                end)
            end
            if channel:execute(true) then
                self.timer:set_period(SECOND_10_MS)
                self:check_clusters()
            end
        end)
    end
end

function RedisDB:login(socket)
    local id, ip, port = socket.id, socket.ip, socket.port
    if not socket:connect(ip, port) then
        log_err("[RedisDB][login] connect db({}:{}:{}) failed!", ip, port, id)
        return false
    end
    socket:set_codec(rediscodec(self.jcodec))
    if self.passwd and #self.passwd > 1 then
        local ok, res = self:auth(socket)
        if not ok or res ~= "OK" then
            log_err("[RedisDB][login] auth db({}:{}:{}) auth failed! because: {}", ip, port, id, res)
            self:delive(socket)
            socket:close()
            return false
        end
    end
    self.connections[id] = nil
    tinsert(self.alives, socket)
    log_info("[RedisDB][login] login db({}:{}:{}) success!", ip, port, id)
    event_mgr:fire_frame(function()
        self:on_socket_alive()
    end)
    return true, SUCCESS
end

function RedisDB:auth(sock)
    return self:commit(sock, "AUTH", self.passwd)
end

function RedisDB:on_socket_alive()
end

function RedisDB:delive(sock)
    if self.cluster then
        local index   = self.slots[sock.port] or 0
        local cluster = self.clusters[index]
        if cluster then
            tdelete(cluster.alives, sock)
        end
    end
    tdelete(self.alives, sock)
    self.connections[sock.id] = sock
end

function RedisDB:on_socket_error(sock, token, err)
    --设置重连
    self:delive(sock)
    self.timer:set_period(SECOND_MS)
    event_mgr:fire_second(function()
        self:check_alive()
    end)
end

function RedisDB:on_socket_recv(sock, session_id, succ, res)
    if self.subscrible then
        self:do_socket_recv(res)
    end
    if session_id > 0 then
        self.res_counter:count_increase()
        thread_mgr:response(session_id, succ, res)
    end
end

function RedisDB:commit(socket, cmd, ...)
    local session_id = thread_mgr:build_session_id()
    if not socket:send_data(session_id, cmd, ...) then
        return false, "send request failed"
    end
    self.req_counter:count_increase()
    local ok, res = thread_mgr:yield(session_id, sformat("redis_comit:%s", cmd), DB_TIMEOUT)
    if not ok then
        log_err("[RedisDB][commit] exec cmd {} failed: {}", cmd, res)
        return ok, res
    end
    local convertor = rconvertors[slower(cmd)]
    if convertor then
        return ok, convertor(res)
    end
    return ok, res
end

function RedisDB:send(cmd, key, ...)
    local sock = self:choose_node(key)
    if sock then
        sock:send_data(0, cmd, key, ...)
    end
end

function RedisDB:direct_send(sock, cmd, ...)
    sock:send_data(0, cmd, ...)
end

function RedisDB:execute(cmd, key, ...)
    local sock = self:choose_node(key)
    if not sock then
        return false, "db not connected"
    end
    return self:commit(sock, cmd, key, ...)
end

return RedisDB
