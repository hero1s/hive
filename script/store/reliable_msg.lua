import("agent/mongo_agent.lua")
local ltimer        = require("ltimer")
local bson          = require("bson")
local bdate         = bson.date
local lnow_ms       = ltimer.now_ms
local tinsert       = table.insert
local log_err       = logger.err
local log_info      = logger.info
local check_success = hive.success
local check_failed  = hive.failed
local PeriodTime    = enum("PeriodTime")

local mongo_agent   = hive.get("mongo_agent")

local ReliableMsg   = class()
local prop          = property(ReliableMsg)
prop:reader("db_name", "")
prop:reader("table_name", "")
prop:reader("ttl", nil)

function ReliableMsg:__init(db_name, table_name, due_day)
    self.ttl        = (due_day or 1) * PeriodTime.DAY_S
    self.db_name    = db_name
    self.table_name = table_name
end

function ReliableMsg:build_index(sharding)
    local indexs = {
        { key = { uuid = 1 }, name = "uuid", unique = true, background = true },
    }
    if not sharding then
        tinsert(indexs, { key = { to = 1 }, name = "to", unique = false, background = true })
    end
    if self.ttl then
        tinsert(indexs, { key = { ttl = 1 }, expireAfterSeconds = 0, name = "ttl", unique = false, background = true })
    end
    local query    = { self.table_name, indexs }
    local ok, code = mongo_agent:create_indexes(query, nil, self.db_name)
    if check_success(code, ok) then
        log_info("[RmsgMgr][build_index] rmsg table %s build due index success", self.table_name)
    end
end

function ReliableMsg:check_indexes(sharding)
    local success = true
    local miss    = {}
    if not mongo_agent:check_indexes({ uuid = 1 }, self.table_name, self.db_name, false) then
        success = false
        tinsert(miss, { db = self.db_name, co = self.table_name, key = { uuid = 1 } })
    end
    if not mongo_agent:check_indexes({ to = 1 }, self.table_name, self.db_name, sharding) then
        success = false
        tinsert(miss, { db = self.db_name, co = self.table_name, key = { to = 1 } })
    end
    if not mongo_agent:check_indexes({ ttl = 1 }, self.table_name, self.db_name, false) then
        success = false
        tinsert(miss, { db = self.db_name, co = self.table_name, key = { ttl = 1 }, expireAfterSeconds = 0 })
    end
    return success, miss
end

-- 查询未处理消息列表
function ReliableMsg:list_message(to)
    local query            = { self.table_name, { to = to, deal_time = 0 }, { _id = 0, ttl = 0 }, { time = 1 } }
    local ok, code, result = mongo_agent:find(query, to, self.db_name)
    if check_success(code, ok) then
        return result
    end
    return {}
end

-- 设置信息为已处理
function ReliableMsg:deal_message(to, timestamp)
    log_info("[RmsgMgr][deal_message] message:%s, %s,%s", self.table_name, to, timestamp)
    local selecter = { ["$and"] = { { to = to }, { time = { ["$lte"] = timestamp } } } }
    local query    = { self.table_name, { ["$set"] = { deal_time = hive.now } }, selecter }
    return mongo_agent:update(query, to, self.db_name)
end

function ReliableMsg:deal_message_by_uuid(uuid, to)
    log_info("[RmsgMgr][deal_message_by_uuid] message:%s,%s", self.table_name, uuid)
    local query = { self.table_name, { ["$set"] = { deal_time = hive.now } }, { uuid = uuid, to = to } }
    return mongo_agent:update(query, hive.id, self.db_name)
end

-- 删除消息
function ReliableMsg:delete_message(to, timestamp)
    log_info("[ReliableMsg][delete_message] delete %s message: %s", self.table_name, to)
    local selecter = { ["$and"] = { { to = to }, { time = { ["$lte"] = timestamp } } } }
    return mongo_agent:delete({ self.table_name, selecter }, hive.id, self.db_name)
end

function ReliableMsg:delete_message_by_uuid(uuid, to)
    log_info("[RmsgMgr][delete_message_by_uuid] delete message: %s", uuid)
    return mongo_agent:delete({ self.table_name, { uuid = uuid, to = to }, true }, hive.id, self.db_name)
end

-- 发送消息
function ReliableMsg:send_message(from, to, body, typ, id)
    local uuid = id or hive.new_guid()
    local doc  = {
        uuid      = uuid,
        from      = from, to = to,
        type      = typ, body = body,
        time      = lnow_ms(),
        deal_time = 0,
    }
    --设置过期ttl字段
    if self.ttl then
        doc.ttl = bdate(hive.now + self.ttl)
    end
    local ok, code, res = mongo_agent:insert({ self.table_name, doc }, to, self.db_name)
    if check_failed(code, ok) then
        log_err("[RmsgMgr][send_message] send message failed: uuid:%s, from:%s, to:%s, doc:%s,code:%s,res:%s",
                uuid, from, to, doc, code, res)
        return false
    else
        log_info("[RmsgMgr][send_message] send message succeed: uuid:%s, from:%s, to:%s, type:%s", uuid, from, to, typ)
    end
    return true
end

return ReliableMsg
