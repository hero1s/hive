--rmsg_mgr.lua
import("agent/mongo_agent.lua")
local bson          = require("bson")
local lcrypt        = require("lcrypt")
local bdate         = bson.date
local log_err       = logger.err
local log_info      = logger.info
local new_guid      = lcrypt.guid_new
local mongo_agent   = hive.get("mongo_agent")
local check_success = hive.success
local PeriodTime    = enum("PeriodTime")
local RmsgMgr       = class()
local prop          = property(RmsgMgr)
prop:reader("db_name", "")
prop:reader("table_name", "")
prop:reader("ttl", nil)

function RmsgMgr:__init(db_name, table_name, due_day)
    self.ttl        = (due_day or 1) * PeriodTime.DAY_S
    self.db_name    = db_name
    self.table_name = table_name
    log_info("[RmsgMgr][init] init rmsg db:%s, table: %s", db_name, table_name)
end

function RmsgMgr:build_index()
    local indexs = {
        { key = { to = 1 }, name = "to", unique = false },
        { key = { uuid = 1 }, name = "uuid", unique = true },
    }
    if self.ttl then
        indexs[#indexs + 1] = { key = { ttl = 1 }, expireAfterSeconds = 0, name = "ttl", unique = false }
    end
    local query    = { self.table_name, indexs }
    local ok, code = mongo_agent:create_indexes(query, 1, self.db_name)
    if ok and check_success(code) then
        log_info("[RmsgMgr][build_index] rmsg table %s build due index success", self.table_name)
    end
end

-- 查询未处理消息列表
function RmsgMgr:list_message(to)
    local query            = { self.table_name, { to = to, deal_time = 0 }, { _id = 0 }, { time = 1 } }
    local ok, code, result = mongo_agent:find(query, to, self.db_name)
    if ok and check_success(code) then
        return result
    end
end

-- 设置信息为已处理
function RmsgMgr:deal_message(to, uuid)
    log_info("[RmsgMgr][deal_message] deal message: %s", uuid)
    local query = { self.table_name, { ["$set"] = { deal_time = hive.now } }, { uuid = uuid } }
    return mongo_agent:update(query, to, self.db_name)
end

-- 删除消息
function RmsgMgr:delete_message(to, uuid)
    log_info("[RmsgMgr][delete_message] delete message: %s", uuid)
    return mongo_agent:delete({ self.table_name, { uuid = uuid } }, to, self.db_name)
end

-- 发送消息
function RmsgMgr:send_message(from, to, typ, body, id)
    local uuid = id or new_guid()
    local doc  = {
        uuid      = uuid,
        from      = from, to = to,
        type      = typ, body = body,
        time      = hive.now,
        deal_time = 0,
    }
    --设置过期ttl字段
    if self.ttl then
        doc.ttl = bdate(hive.now + self.ttl)
    end
    local ok = mongo_agent:insert({ self.table_name, doc }, to, self.db_name)
    if not ok then
        log_err("[RmsgMgr][send_message] send message failed: uuid:%s, from:%s, to:%s, doc:%s", uuid, from, to, doc)
    else
        log_info("[RmsgMgr][send_message] send message succeed: uuid:%s, from:%s, to:%s, type:%s", uuid, from, to, typ)
    end
    return ok
end

return RmsgMgr
