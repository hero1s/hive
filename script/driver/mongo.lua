--mongo.lua
local bson          = require("bson")
local lmongo        = require("mongo")
local lcrypt        = require("lcrypt")
local Socket        = import("driver/socket.lua")

local log_err       = logger.err
local log_info      = logger.info
local qhash         = hive.hash
local tunpack       = table.unpack
local tinsert       = table.insert
local tis_array     = table_ext.is_array
local tdeep_copy    = table_ext.deep_copy
local tjoin         = table_ext.join
local ssub          = string.sub
local sgsub         = string.gsub
local sformat       = string.format
local sgmatch       = string.gmatch
local mtointeger    = math.tointeger
local lmd5          = lcrypt.md5
local lsha1         = lcrypt.sha1
local lrandomkey    = lcrypt.randomkey
local lb64encode    = lcrypt.b64_encode
local lb64decode    = lcrypt.b64_decode
local lhmac_sha1    = lcrypt.hmac_sha1
local lxor_byte     = lcrypt.xor_byte

local mreply        = lmongo.reply
local mopmsg        = lmongo.op_msg
local mlength       = lmongo.length
local bson_decode   = bson.decode
local bson_encode_o = bson.encode_order

local timer_mgr     = hive.get("timer_mgr")
local update_mgr    = hive.get("update_mgr")
local thread_mgr    = hive.get("thread_mgr")

local SECOND_MS     = hive.enum("PeriodTime", "SECOND_MS")
local SECOND_10_MS  = hive.enum("PeriodTime", "SECOND_10_MS")
local DB_TIMEOUT    = hive.enum("NetwkTime", "DB_CALL_TIMEOUT")
local POOL_COUNT    = environ.number("HIVE_DB_POOL_COUNT", 9)

local MongoDB       = class()
local prop          = property(MongoDB)
prop:reader("name", "")         --dbname
prop:reader("user", nil)        --user
prop:reader("passwd", nil)      --passwd
prop:reader("executer", nil)    --执行者
prop:reader("timer_id", nil)    --timer_id
prop:reader("cursor_id", nil)   --cursor_id
prop:reader("connections", {})  --connections
prop:reader("sessions", {})     --sessions
prop:reader("readpref", nil)    --readPreference
prop:reader("auth_source", "admin") --authSource

function MongoDB:__init(conf)
    self.user      = conf.user
    self.passwd    = conf.passwd
    self.name      = conf.db
    self.cursor_id = bson.int64(0)
    self:choose_host(conf.hosts)
    self:set_options(conf.opts)
    --attach_hour
    update_mgr:attach_hour(self)
end

function MongoDB:__release()
    self:close()
end

function MongoDB:close()
    for sock in pairs(self.connections) do
        sock:close()
    end
    if self.timer_id then
        timer_mgr:unregister(self.timer_id)
        self.timer_id = nil
    end
end

function MongoDB:set_executer(id)
    local index   = qhash(id, POOL_COUNT)
    self.executer = self.connections[index]
end

function MongoDB:choose_host(hosts)
    if not next(hosts) then
        log_err("[MongoDB][choose_host] mongo config err: hosts is empty")
        return
    end
    local count = POOL_COUNT
    while count > 0 do
        for ip, port in pairs(hosts) do
            local socket            = Socket(self, ip, port)
            socket.sessions         = {}
            self.connections[count] = socket
            count                   = count - 1
            break
        end
    end
    thread_mgr:entry(self:address(), function()
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

function MongoDB:check_alive()
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

function MongoDB:on_hour()
    for _, sock in pairs(self.connections) do
        if not sock:is_alive() then
            self.executer = sock
            self:runCommand("ping")
        end
    end
end

function MongoDB:login(socket, no)
    local ip, port = socket.ip, socket.port
    local ok, err  = socket:connect(ip, port)
    if not ok then
        log_err("[MongoDB][login] connect db(%s:%s:%s:%s) failed: %s!", ip, port, self.name, no, err)
        return
    end
    self.executer = socket
    if #self.user > 1 and #self.passwd > 1 then
        local aok, aerr = self:auth(self.user, self.passwd)
        if not aok then
            socket:close()
            log_err("[MongoDB][login] auth db(%s:%s:%s:%s,[%s:%s]) failed! because: %s", ip, port, self.name, no, self.user, self.passwd, aerr)
            return
        end
    end
    log_info("[MongoDB][on_second] connect db(%s:%s:%s:%s) success!", ip, port, self.name, no)
end

local function salt_password(password, salt, iter)
    salt         = salt .. "\0\0\0\1"
    local output = lhmac_sha1(password, salt)
    local inter  = output
    for i = 2, iter do
        inter  = lhmac_sha1(password, inter)
        output = lxor_byte(output, inter)
    end
    return output
end

---排序参数/联合主键需要控制顺序,将参数写成数组模式{{k1=1},{k2=2}},单参数或不需要优先级可以{k1=1,k2=2}
function MongoDB:sort_param(param)
    local dst = {}
    if type(param) == "table" then
        if tis_array(param) then
            for _, p in ipairs(param) do
                for k, v in pairs(p) do
                    tinsert(dst, k)
                    tinsert(dst, v)
                end
            end
        else
            for k, v in pairs(param) do
                tinsert(dst, k)
                tinsert(dst, v)
            end
        end
    else
        log_err("[MongoDB][sort_param]sort_param is not table:%s", param)
    end
    return bson_encode_o(tunpack(dst))
end

function MongoDB:auth(username, password)
    local nonce              = lb64encode(lrandomkey())
    local user               = sgsub(sgsub(username, '=', '=3D'), ',', '=2C')
    local first_bare         = "n=" .. user .. ",r=" .. nonce
    local sasl_start_payload = lb64encode("n,," .. first_bare)
    local sok, sdoc          = self:adminCommand("saslStart", 1, "autoAuthorize", 1, "mechanism", "SCRAM-SHA-1", "payload", sasl_start_payload)
    if not sok then
        log_err("[MongoDB][auth] saslStart err:%s", sdoc)
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
    local salted_pass        = salt_password(pbkdf2_key, lb64decode(salt), iterations)
    local client_key         = lhmac_sha1(salted_pass, "Client Key")
    local stored_key         = lsha1(client_key)
    local auth_msg           = first_bare .. ',' .. str_payload_start .. ',' .. without_proof
    local client_sig         = lhmac_sha1(stored_key, auth_msg)
    local client_key_xor_sig = lxor_byte(client_key, client_sig)
    local client_proof       = "p=" .. lb64encode(client_key_xor_sig)
    local client_final       = lb64encode(without_proof .. ',' .. client_proof)

    local cok, cdoc          = self:adminCommand("saslContinue", 1, "conversationId", conversationId, "payload", client_final)
    if not cok then
        log_err("[MongoDB][auth] saslContinue err:%s", cdoc)
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
        log_err("[MongoDB][auth] Server returned an invalid signature.")
        return false
    end
    if not cdoc.done then
        local ccok, ccdoc = self:adminCommand("saslContinue", 1, "conversationId", conversationId, "payload", "")
        if not ccok or not ccdoc.done then
            return false, "SASL conversation failed to complete."
        end
    end
    return true
end

function MongoDB:on_socket_error(sock, token, err)
    log_err("[MongoDB][on_socket_error] token:%s,err:%s", token, err)
    for session_id in pairs(sock.sessions) do
        thread_mgr:response(session_id, false, err)
    end
    sock.sessions = {}
    --检查活跃
    thread_mgr:entry(self:address(), function()
        self:check_alive()
    end)
end

function MongoDB:decode_reply(succ, documents)
    local doc = bson_decode(documents)
    if doc.writeErrors then
        return false, doc.writeErrors[1].errmsg
    end
    if doc.writeConcernError then
        return false, doc.writeConcernError.errmsg
    end
    if succ and doc.ok == 1 then
        return succ, doc
    end
    return false, doc.errmsg or doc["$err"]
end

function MongoDB:on_socket_recv(sock, token)
    local sessions = sock.sessions
    while true do
        local hdata = sock:peek(4)
        if not hdata then
            break
        end
        local length = mlength(hdata)
        local bdata  = sock:peek(length, 4)
        if not bdata then
            break
        end
        sock:pop(4 + length)
        local reply, session_id, documents = mreply(bdata)
        local cost_time                    = hive.clock_ms - (sessions[session_id] or 0)
        if cost_time > DB_TIMEOUT then
            log_err("[MongoDB][on_socket_recv] the op_session:%s, timeout:%s", session_id, cost_time)
        end
        sessions[session_id] = nil
        local succ, doc      = self:decode_reply(reply, documents)
        thread_mgr:response(session_id, succ, doc)
    end
end

function MongoDB:op_msg(bson_cmd)
    local sock = self.executer
    if not sock then
        return false, "db not connected"
    end
    local session_id = thread_mgr:build_session_id()
    local msg        = mopmsg(session_id, 0, bson_cmd)
    if not sock:send(msg) then
        return false, "send failed"
    end
    sock.sessions[session_id] = hive.clock_ms
    return thread_mgr:yield(session_id, "mongo_op_msg", DB_TIMEOUT)
end

function MongoDB:adminCommand(cmd, cmd_v, ...)
    local bson_cmd = bson_encode_o(cmd, cmd_v, "$db", self.auth_source, ...)
    return self:op_msg(bson_cmd)
end

function MongoDB:runCommand(cmd, cmd_v, ...)
    local bson_cmd = bson_encode_o(cmd, cmd_v or 1, "$db", self.name, ...)
    return self:op_msg(bson_cmd)
end

function MongoDB:sendCommand(cmd, cmd_v, ...)
    if not self.executer then
        return false, "db not connected"
    end
    local bson_cmd = bson_encode_o(cmd, cmd_v or 1, "$db", self.name, "writeConcern", { w = 0 }, ...)
    local msg      = mopmsg(0, 2, bson_cmd)
    self.executer:send(msg)
    return true
end

function MongoDB:drop_collection(co_name)
    return self:runCommand("drop", co_name)
end

-- 参数说明
-- indexes={{key={open_id=1,platform_id=1},name="open_id-platform_id",unique=true}, }
function MongoDB:create_indexes(co_name, indexes)
    local tindexs = tdeep_copy(indexes)
    for _, v in ipairs(tindexs) do
        v.key = self:sort_param(v.key)
    end
    local succ, doc = self:runCommand("createIndexes", co_name, "indexes", tindexs)
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

function MongoDB:update(co_name, update, selector, upsert, multi)
    local cmd_data = { q = selector, u = update, upsert = upsert, multi = multi }
    return self:runCommand("update", co_name, "updates", { cmd_data })
end

function MongoDB:delete(co_name, selector, onlyone)
    local cmd_data = { q = selector, limit = onlyone and 1 or 0 }
    return self:runCommand("delete", co_name, "deletes", { cmd_data })
end

function MongoDB:count(co_name, query, limit, skip)
    local succ, doc = self:runCommand("count", co_name, "query", query, "limit", limit or 0, "skip", skip or 0)
    if not succ then
        return succ, doc
    end
    return succ, mtointeger(doc.n)
end

function MongoDB:find_one(co_name, query, projection)
    local succ, reply = self:runCommand("find", co_name, "$readPreference", self.readpref, "filter", query, "projection" or {}, projection, "limit", 1)
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

function MongoDB:find(co_name, query, projection, sortor, limit, skip)
    if sortor and next(sortor) then
        sortor = self:sort_param(sortor)
    end
    local succ, reply = self:runCommand("find", co_name, "$readPreference", self.readpref, "filter", query, "projection", projection or {}, "sort", sortor or {}, "limit", limit or 100, "skip", skip or 0)
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

return MongoDB
