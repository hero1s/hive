--mongo.lua
local bson          = require("bson")
local lmongo        = require("mongo")
local lcrypt        = require("lcrypt")
local Socket        = import("driver/socket.lua")

local ipairs        = ipairs
local log_err       = logger.err
local log_info      = logger.info
local tunpack       = table.unpack
local tinsert       = table.insert
local tis_array     = table_ext.is_array
local tdeep_copy    = table_ext.deep_copy
local ssub          = string.sub
local sgsub         = string.gsub
local sformat       = string.format
local sgmatch       = string.gmatch
local lmd5          = lcrypt.md5
local lsha1         = lcrypt.sha1
local lrandomkey    = lcrypt.randomkey
local lb64encode    = lcrypt.b64_encode
local lb64decode    = lcrypt.b64_decode
local lhmac_sha1    = lcrypt.hmac_sha1
local lxor_byte     = lcrypt.xor_byte
local mmore         = lmongo.more
local mreply        = lmongo.reply
local mquery        = lmongo.query
local mlength       = lmongo.length
local bson_encode   = bson.encode
local bson_decode   = bson.decode
local bson_encode_o = bson.encode_order
local mtointeger    = math.tointeger

local empty_bson    = bson_encode({})

local update_mgr    = hive.get("update_mgr")
local thread_mgr    = hive.get("thread_mgr")

local ONCE_QUERY    = 100
local DB_TIMEOUT    = hive.enum("NetwkTime", "DB_CALL_TIMEOUT")

local MongoDB       = class()
local prop          = property(MongoDB)
prop:reader("ip", nil)          --mongo地址
prop:reader("sock", nil)        --网络连接对象
prop:reader("name", "")         --dbname
prop:reader("db_cmd", "")       --默认cmd
prop:reader("port", 27017)      --mongo端口
prop:reader("user", nil)        --user
prop:reader("passwd", nil)      --passwd
prop:reader("session_id", nil)  --session_id

function MongoDB:__init(conf)
    self.ip     = conf.host
    self.port   = conf.port
    self.user   = conf.user
    self.passwd = conf.passwd
    self.db     = conf.db
    self.db_cmd = conf.db .. "." .. "$cmd"
    self.sock   = Socket(self)
    --attach_second
    update_mgr:attach_minute(self)
    update_mgr:attach_second(self)
end

function MongoDB:__release()
    self:close()
end

function MongoDB:close()
    if self.sock then
        self.sock:close()
    end
end

function MongoDB:on_minute()
    if self.sock:is_alive() and not self:ping() then
        self:close()
    end
end

function MongoDB:on_second()
    if not self.sock:is_alive() then
        if not self.sock:connect(self.ip, self.port) then
            log_err("[MongoDB][on_second] connect db(%s:%s:%s) failed!", self.ip, self.port, self.db)
            return
        end
        if self.user and self.passwd and self.user:len() > 1 and self.passwd:len() > 1 then
            local ok, err = self:auth(self.user, self.passwd)
            if not ok then
                log_err("[MongoDB][on_second] auth db(%s:%s) failed! because: %s", self.ip, self.port, err)
                return
            end
        end
        log_info("[MongoDB][on_second] connect db(%s:%s:%s) success!", self.ip, self.port, self.db)
    end
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

--排序参数/联合主键需要控制顺序,将参数写成数组模式{{k1=1},{k2=2}},单参数或不需要优先级可以{k1=1,k2=2}
local function sort_param(param)
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
        log_err("sort_param is not table:%s", param)
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
        log_err("Server returned an invalid signature.")
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
    if self.session_id then
        thread_mgr:response(self.session_id, false, err)
    end
end

function MongoDB:on_socket_recv(sock, token)
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
        local documents                        = {}
        self.session_id                        = nil
        local succ, session_id, doc, cursor_id = mreply(bdata, documents)
        thread_mgr:response(session_id, succ, doc, cursor_id, documents)
    end
end

function MongoDB:mongo_result(succ, doc)
    if type(doc) == "string" then
        return succ, doc
    end
    if type(doc) == "userdata" then
        doc = bson_decode(doc) or {}
    end
    if doc.writeErrors then
        return false, doc.writeErrors[1].errmsg
    end
    if doc.writeConcernError then
        return false, doc.writeConcernError.errmsg
    end
    if succ and doc.ok == 1 then
        return true, doc
    end
    return false, doc.errmsg or doc["$err"]
end

function MongoDB:_query(full_name, query, selector, query_num, skip, flag)
    if not self.sock then
        return false, "db not connected"
    end
    local bson_query    = query or empty_bson
    local bson_selector = selector or empty_bson
    local session_id    = thread_mgr:build_session_id()
    local pack          = mquery(session_id, flag or 0, full_name, skip or 0, query_num or 1, bson_query, bson_selector)
    if not self.sock:send(pack) then
        return false, "send failed"
    end
    self.session_id = session_id
    return thread_mgr:yield(session_id, "mongo_query", DB_TIMEOUT)
end

function MongoDB:_more(full_name, cursor, query_num)
    if not self.sock then
        return false, "db not connected"
    end
    local session_id = thread_mgr:build_session_id()
    local pack       = mmore(session_id, full_name, query_num or 0, cursor)
    if not self.sock:send(pack) then
        return false, "send failed"
    end
    self.session_id                        = session_id
    local succ, doc, new_cursor, documents = thread_mgr:yield(session_id, "mongo_more", DB_TIMEOUT)
    if not succ then
        return self:mongo_result(succ, doc)
    end
    return true, new_cursor, documents
end

function MongoDB:adminCommand(cmd, cmd_v, ...)
    local bson_cmd  = bson_encode_o(cmd, cmd_v, ...)
    local succ, doc = self:_query("admin.$cmd", bson_cmd)
    return self:mongo_result(succ, doc)
end

--https://docs.mongodb.com/manual/reference/command/
function MongoDB:runCommand(cmd, cmd_v, ...)
    local bson_cmd
    if not cmd_v then
        bson_cmd = bson_encode_o(cmd, 1)
    else
        bson_cmd = bson_encode_o(cmd, cmd_v, ...)
    end
    local succ, doc = self:_query(self.db_cmd, bson_cmd)
    return self:mongo_result(succ, doc)
end

function MongoDB:ping()
    local ok, _ = self:runCommand("ping", 1)
    return ok
end

function MongoDB:drop_collection(collection)
    return self:runCommand("drop", collection)
end

-- 参数说明
-- indexes={{key={open_id=1,platform_id=1},name="open_id-platform_id",unique=true}, }
function MongoDB:create_indexes(collection, indexes)
    local tindexs = tdeep_copy(indexes)
    for _, v in ipairs(tindexs) do
        v.key = sort_param(v.key)
    end
    local succ, doc = self:runCommand("createIndexes", collection, "indexes", tindexs)
    if not succ then
        return succ, doc
    end
    return succ
end

function MongoDB:drop_indexes(collection, index_name)
    local succ, doc = self:runCommand("dropIndexes", collection, "index", index_name)
    if not succ then
        return succ, doc
    end
    return succ
end

function MongoDB:insert(collection, doc)
    return self:runCommand("insert", collection, "documents", { bson_encode(doc) })
end

function MongoDB:update(collection, update, selector, upsert, multi)
    local bson_data = bson_encode({ q = selector, u = update, upsert = upsert, multi = multi })
    return self:runCommand("update", collection, "updates", { bson_data })
end

function MongoDB:delete(collection, selector, onlyone)
    local bson_data = bson_encode({ q = selector, limit = onlyone and 1 or 0 })
    return self:runCommand("delete", collection, "deletes", { bson_data })
end

function MongoDB:count(collection, selector, limit, skip)
    local cmds = {}
    if limit then
        cmds[#cmds + 1] = "limit"
        cmds[#cmds + 1] = limit
    end
    if skip then
        cmds[#cmds + 1] = "skip"
        cmds[#cmds + 1] = skip
    end
    local succ, doc = self:runCommand("count", collection, "query", selector, tunpack(cmds))
    if not succ then
        return succ, doc
    end
    return succ, mtointeger(doc.n)
end

function MongoDB:find_one(collection, selector, fields)
    local full_name     = self.db .. "." .. collection
    local bson_selector = selector and bson_encode(selector)
    local bson_fields   = fields and bson_encode(fields)
    local succ, doc     = self:_query(full_name, bson_selector, bson_fields)
    if succ then
        return succ, bson_decode(doc)
    end
    return succ, doc
end

function MongoDB:build_results(documents, results, limit)
    for i, _doc in ipairs(documents) do
        if limit and #results >= limit then
            break
        end
        results[#results + 1] = bson_decode(_doc)
    end
end

function MongoDB:find(collection, selector, fields, sortor, limit)
    local query_num_once = limit or ONCE_QUERY
    local full_name      = self.db .. "." .. collection
    local bson_fields    = fields and bson_encode(fields)
    if sortor and next(sortor) then
        selector = { ["$query"] = selector, ["$orderby"] = sort_param(sortor) }
    end
    local bson_selector                = selector and bson_encode(selector)
    local succ, doc, cursor, documents = self:_query(full_name, bson_selector, bson_fields, query_num_once)
    if not succ then
        return self:mongo_result(succ, doc)
    end
    local results = {}
    self:build_results(documents, results, limit)
    while cursor do
        if limit and #results >= limit then
            break
        end
        local _succ, _cursor_oe, _documents = self:_more(full_name, cursor, query_num_once)
        if not _succ then
            return _succ, _cursor_oe
        end
        self:build_results(_documents, results, limit)
        cursor = _cursor_oe
    end
    return true, results
end

function MongoDB:find_and_modify(collection, update, selector, upsert, fields)
    local doc = { query = selector, update = update, fields = fields, upsert = upsert, new = true }
    local cmd = { "findAndModify", collection };
    for k, v in pairs(doc) do
        cmd[#cmd + 1] = k
        cmd[#cmd + 1] = v
    end
    return self:runCommand(tunpack(cmd))
end

return MongoDB
