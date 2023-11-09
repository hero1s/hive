--mongo.lua
local Socket       = import("driver/socket.lua")
local log_warn     = logger.warn
local log_err      = logger.err
local log_info     = logger.info
local qhash        = hive.hash
local hdefer       = hive.defer
local makechan     = hive.make_channel
local tinsert      = table.insert
local tunpack      = table.unpack
local tdelete      = table_ext.delete
local tjoin        = table_ext.join
local mrandom      = math_ext.random
local ssub         = string.sub
local sgsub        = string.gsub
local sformat      = string.format
local sgmatch      = string.gmatch
local mtointeger   = math.tointeger
local lmd5         = crypt.md5
local lsha1        = crypt.sha1
local bsonpairs    = bson.pairs
local lrandomkey   = crypt.randomkey
local lb64encode   = crypt.b64_encode
local lb64decode   = crypt.b64_decode
local lhmac_sha1   = crypt.hmac_sha1
local lxor_byte    = crypt.xor_byte
local lclock_ms    = timer.clock_ms

local timer_mgr    = hive.get("timer_mgr")
local event_mgr    = hive.get("event_mgr")
local update_mgr   = hive.get("update_mgr")
local thread_mgr   = hive.get("thread_mgr")

local SUCCESS      = hive.enum("KernCode", "SUCCESS")
local FAST_MS      = hive.enum("PeriodTime", "FAST_MS")
local SECOND_MS    = hive.enum("PeriodTime", "SECOND_MS")
local SECOND_10_MS = hive.enum("PeriodTime", "SECOND_10_MS")
local DB_TIMEOUT   = hive.enum("NetwkTime", "DB_CALL_TIMEOUT")
local POOL_COUNT   = environ.number("HIVE_DB_POOL_COUNT", 3)

local MongoDB      = class()
local prop         = property(MongoDB)
prop:reader("name", "")         --dbname
prop:reader("user", nil)        --user
prop:reader("passwd", nil)      --passwd
prop:reader("salted_pass", nil) --salted_pass
prop:reader("executer", nil)    --执行者
prop:reader("timer_id", nil)    --timer_id
prop:reader("cursor_id", nil)   --cursor_id
prop:reader("sort_doc", nil)    --sort_doc
prop:reader("connections", {})  --connections
prop:reader("sessions", {})     --sessions
prop:reader("readpref", { mode = "primary" })    --readPreference
prop:reader("auth_source", "admin") --authSource
prop:reader("alives", {})           --alives
prop:reader("req_counter", nil)
prop:reader("res_counter", nil)

function MongoDB:__init(conf)
    self.user      = conf.user
    self.passwd    = conf.passwd
    self.name      = conf.db
    self.sort_doc  = bson.doc()
    self.cursor_id = bson.int64(0)
    self.codec     = bson.mongocodec()
    self:set_options(conf.opts)
    self:setup_pool(conf.hosts)
    --attach_hour
    update_mgr:attach_hour(self)
    --counter
    self.req_counter = hive.make_sampling(sformat("mongo %s req", self.name))
    self.res_counter = hive.make_sampling(sformat("mongo %s res", self.name))
end

function MongoDB:__release()
    self:close()
end

function MongoDB:close()
    for sock in pairs(self.alives) do
        sock:close()
    end
    for sock in pairs(self.connections) do
        sock:close()
    end
    timer_mgr:unregister(self.timer_id)
    self.connections = {}
    self.alives      = {}
end

function MongoDB:set_executer(id)
    local count = #self.alives
    if count > 0 then
        local index   = qhash(id or mrandom(), count)
        self.executer = self.alives[index]
        return true
    end
    return false
end

function MongoDB:setup_pool(hosts)
    if not next(hosts) then
        log_err("[MongoDB][setup_pool] mongo config err: hosts is empty")
        return
    end
    local count = 1
    for _, host in pairs(hosts) do
        for c = 1, POOL_COUNT do
            local socket            = Socket(self, host[1], host[2])
            self.connections[count] = socket
            socket.sessions         = {}
            socket:set_id(count)
            count = count + 1
        end
    end
    self.timer_id = timer_mgr:register(0, SECOND_MS, -1, function()
        self:check_alive()
    end)
end

function MongoDB:set_options(opts)
    for key, value in pairs(opts) do
        if key == "readPreference" then
            self.readpref = { mode = value }
        elseif key == "authSource" then
            self.auth_source = value
        end
    end
end

function MongoDB:available()
    return #self.alives > 0
end

function MongoDB:check_alive()
    if next(self.connections) then
        thread_mgr:entry(self:address(), function()
            local channel = makechan("check mongo")
            for _, sock in pairs(self.connections) do
                channel:push(function()
                    return self:login(sock)
                end)
            end
            if channel:execute(true) then
                timer_mgr:set_period(self.timer_id, SECOND_10_MS)
            end
            self:set_executer()
        end)
    end
end

function MongoDB:on_hour()
    for _, sock in pairs(self.alives) do
        self.executer = sock
        self:sendCommand("ping")
    end
end

function MongoDB:login(socket)
    local id, ip, port = socket.id, socket.ip, socket.port
    local ok, err      = socket:connect(ip, port)
    if not ok then
        log_err("[MongoDB][login] connect db({}:{}:{}:{}) failed: {}!", ip, port, self.name, id, err)
        return false
    end
    socket:set_codec(self.codec)
    if #self.user > 1 and #self.passwd > 1 then
        local aok, aerr = self:auth(socket, self.user, self.passwd)
        if not aok then
            log_err("[MongoDB][login] auth db({}:{}:{}:{}) failed! because: {}", ip, port, self.name, id, aerr)
            self:delive(socket)
            socket:close()
            return false
        end
    end
    self.connections[id] = nil
    tinsert(self.alives, socket)
    log_info("[MongoDB][login] connect db({}:{}:{}:{}) success!", ip, port, self.name, id)
    return true, SUCCESS
end

function MongoDB:salt_password(password, salt, iter)
    if self.salted_pass then
        return self.salted_pass
    end
    salt         = salt .. "\0\0\0\1"
    local output = lhmac_sha1(password, salt)
    local inter  = output
    for i = 2, iter do
        inter  = lhmac_sha1(password, inter)
        output = lxor_byte(output, inter)
    end
    self.salted_pass = output
    return output
end

function MongoDB:auth(sock, username, password)
    local nonce              = lb64encode(lrandomkey())
    local user               = sgsub(sgsub(username, '=', '=3D'), ',', '=2C')
    local first_bare         = "n=" .. user .. ",r=" .. nonce
    local sasl_start_payload = lb64encode("n,," .. first_bare)
    local sok, sdoc          = self:adminCommand(sock, "saslStart", 1, "autoAuthorize", 1, "mechanism", "SCRAM-SHA-1", "payload", sasl_start_payload)
    if not sok then
        return sok, sdoc
    end
    local conversationId    = sdoc['conversationId']
    local str_payload_start = lb64decode(sdoc['payload'])
    local payload_start     = {}
    for k, v in sgmatch(str_payload_start, "(%w+)=([^,]*)") do
        payload_start[k] = v
    end
    local salt       = payload_start['s']
    local rnonce     = payload_start['r']
    local iterations = tonumber(payload_start['i'])
    if not ssub(rnonce, 1, 12) == nonce then
        return false, "Server returned an invalid nonce."
    end
    local without_proof      = "c=biws,r=" .. rnonce
    local pbkdf2_key         = lmd5(sformat("%s:mongo:%s", username, password), 1)
    local salted_pass        = self:salt_password(pbkdf2_key, lb64decode(salt), iterations)
    local client_key         = lhmac_sha1(salted_pass, "Client Key")
    local stored_key         = lsha1(client_key)
    local auth_msg           = first_bare .. ',' .. str_payload_start .. ',' .. without_proof
    local client_sig         = lhmac_sha1(stored_key, auth_msg)
    local client_key_xor_sig = lxor_byte(client_key, client_sig)
    local client_proof       = "p=" .. lb64encode(client_key_xor_sig)
    local client_final       = lb64encode(without_proof .. ',' .. client_proof)

    local cok, cdoc          = self:adminCommand(sock, "saslContinue", 1, "conversationId", conversationId, "payload", client_final)
    if not cok then
        return cok, cdoc
    end
    local payload_continue     = {}
    local str_payload_continue = lb64decode(cdoc['payload'])
    for k, v in sgmatch(str_payload_continue, "(%w+)=([^,]*)") do
        payload_continue[k] = v
    end
    local server_key = lhmac_sha1(salted_pass, "Server Key")
    local server_sig = lb64encode(lhmac_sha1(server_key, auth_msg))
    if payload_continue['v'] ~= server_sig then
        return false, "Server returned an invalid signature."
    end
    if not cdoc.done then
        local ccok, ccdoc = self:adminCommand(sock, "saslContinue", 1, "conversationId", conversationId, "payload", "")
        if not ccok or not ccdoc.done then
            return false, "SASL conversation failed to complete."
        end
    end
    return true
end

function MongoDB:delive(sock)
    tdelete(self.alives, sock)
    self.connections[sock.id] = sock
end

function MongoDB:on_socket_error(sock, token, err)
    --清空状态
    if sock == self.executer then
        self.executer = nil
        self:set_executer()
    end
    self:delive(sock)
    --设置重连
    timer_mgr:set_period(self.timer_id, SECOND_MS)
    event_mgr:fire_second(function()
        self:check_alive()
    end)
    for session_id, cmd in pairs(sock.sessions) do
        log_warn("[MongoDB][on_socket_error] drop cmd {}-{})!", cmd, session_id)
        thread_mgr:response(session_id, false, err)
    end
    sock.sessions = {}
end

function MongoDB:decode_reply(result)
    if result.writeErrors then
        return false, result.writeErrors[1].errmsg
    end
    if result.writeConcernError then
        return false, result.writeConcernError.errmsg
    end
    if result.ok == 1 then
        return true, result
    end
    return false, result.errmsg or result["$err"]
end

function MongoDB:on_socket_recv(sock, session_id, result)
    if session_id > 0 then
        self.res_counter:count_increase()
        local succ, doc = self:decode_reply(result)
        thread_mgr:response(session_id, succ, doc)
    end
end

function MongoDB:op_msg(sock, session_id, cmd, ...)
    if not sock then
        return false, "db not connected"
    end
    local tick = lclock_ms()
    if not sock:send_data(session_id, cmd, ...) then
        return false, "send failed"
    end
    sock.sessions[session_id] = cmd
    self.req_counter:count_increase()
    local _<close> = hdefer(function()
        sock.sessions[session_id] = nil
        local utime               = lclock_ms() - tick
        if utime > FAST_MS then
            log_warn("[MongoDB][op_msg] cmd ({}:{}) execute so big {}!", cmd, session_id, utime)
        end
    end)
    return thread_mgr:yield(session_id, cmd, DB_TIMEOUT)
end

function MongoDB:adminCommand(sock, cmd, cmd_v, ...)
    local session_id = thread_mgr:build_session_id()
    return self:op_msg(sock, session_id, cmd, cmd_v, "$db", "admin", ...)
end

function MongoDB:runCommand(cmd, cmd_v, ...)
    local session_id = thread_mgr:build_session_id()
    return self:op_msg(self.executer, session_id, cmd, cmd_v or 1, "$db", self.name, ...)
end

function MongoDB:sendCommand(cmd, cmd_v, ...)
    self.executer:send_data(0, cmd, cmd_v or 1, "$db", self.name, "writeConcern", { w = 0 }, ...)
end

function MongoDB:drop_collection(co_name)
    return self:runCommand("drop", co_name)
end

function MongoDB:get_indexes(co_name)
    local succ, reply = self:runCommand("listIndexes", co_name)
    if not succ then
        return succ, reply
    end
    if type(reply) == "table" and reply.cursor then
        local documents = reply.cursor.firstBatch
        return succ, documents
    end
    return succ
end

-- 参数说明
-- indexes: {{key={open_id=1}, name="open_id", unique=true} }
-- indexes: {{key={open_id,1,platform_id,1}, name="open_id-platform_id", unique=true} }
function MongoDB:create_indexes(co_name, indexes)
    for _, index in pairs(indexes) do
        index.key = self:format_pairs(index.key)
    end
    local succ, doc = self:runCommand("createIndexes", co_name, "indexes", indexes)
    if not succ then
        return succ, doc
    end
    return succ
end

function MongoDB:drop_indexes(co_name, index_name)
    local succ, doc = self:runCommand("dropIndexes", co_name, "index", index_name)
    if not succ then
        return succ, doc
    end
    return succ
end

function MongoDB:insert(co_name, doc)
    return self:runCommand("insert", co_name, "documents", { doc })
end

function MongoDB:unsafe_insert(co_name, doc)
    return self:sendCommand("insert", co_name, "documents", { doc })
end

function MongoDB:update(co_name, update, selector, upsert, multi)
    local cmd_data = { q = selector, u = update, upsert = upsert, multi = multi }
    return self:runCommand("update", co_name, "updates", { cmd_data })
end

function MongoDB:unsafe_update(co_name, update, selector, upsert, multi)
    local cmd_data = { q = selector, u = update, upsert = upsert, multi = multi }
    return self:sendCommand("update", co_name, "updates", { cmd_data })
end

function MongoDB:delete(co_name, selector, onlyone)
    local cmd_data = { q = selector, limit = onlyone and 1 or 0 }
    return self:runCommand("delete", co_name, "deletes", { cmd_data })
end

function MongoDB:unsafe_delete(co_name, selector, onlyone)
    local cmd_data = { q = selector, limit = onlyone and 1 or 0 }
    return self:sendCommand("delete", co_name, "deletes", { cmd_data })
end

function MongoDB:count(co_name, query, limit, skip)
    local succ, doc = self:runCommand("count", co_name, "query", query, "limit", limit or 0, "skip", skip or 0)
    if not succ then
        return succ, doc
    end
    return succ, mtointeger(doc.n)
end

function MongoDB:find_one(co_name, query, projection)
    local succ, reply = self:runCommand("find", co_name, "filter", query, "projection" or {}, projection, "limit", 1)
    if not succ then
        return succ, reply
    end
    if type(reply) == "table" and reply.cursor then
        local documents = reply.cursor.firstBatch
        if #documents > 0 then
            return succ, documents[1]
        end
    end
    return succ
end

function MongoDB:format_pairs(args, doc)
    if args then
        if type(next(args)) == "string" then
            return args
        end
        if doc then
            tinsert(args, doc)
        end
        return bsonpairs(tunpack(args))
    end
end

-- 参数说明
--sort: {k1=1} / {k1,1,k2,-1,k3,-1}
function MongoDB:find(co_name, query, projection, sortor, limit, skip)
    local fsortor     = self:format_pairs(sortor, self.sort_doc)
    local succ, reply = self:runCommand("find", co_name, "filter", query,
                                        "projection", projection or {}, "sort", fsortor or {}, "limit", limit or 100, "skip", skip or 0)
    if not succ then
        return succ, reply
    end
    local results = {}
    local cursor  = reply.cursor
    while cursor do
        local documents = cursor.firstBatch or cursor.nextBatch
        tjoin(documents, results)
        if not cursor.id or cursor.id == 0 then
            break
        end
        if limit and #results >= limit then
            break
        end
        self.cursor_id       = cursor.id
        local msucc, moreply = self:runCommand("getMore", bson.int64(self.cursor_id), "collection", co_name)
        if not msucc then
            return msucc, moreply
        end
        cursor = moreply.cursor
    end
    return true, results
end

function MongoDB:find_and_modify(co_name, update, selector, upsert, fields, new)
    return self:runCommand("findAndModify", co_name, "query", selector, "update", update, "fields", fields, "upsert", upsert, "new", new)
end

-- https://docs.mongodb.com/manual/reference/command/aggregate/
-- collection:aggregate({ { ["$project"] = {tags = 1} } }, {cursor={}})
-- @param pipeline: array
-- @param options: map
-- @return
function MongoDB:aggregate(co_name, pipeline, options)
    local cmd = { "aggregate", co_name, "pipeline", pipeline }
    for k, v in pairs(options) do
        tinsert(cmd, k)
        tinsert(cmd, v)
    end
    return self:runCommand(tunpack(cmd))
end

return MongoDB
