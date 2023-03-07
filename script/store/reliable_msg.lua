import("agent/mongo_agent.lua")
import("agent/redis_agent.lua")

local bson          = require("bson")
local bdate         = bson.date
local sformat       = string.format
local tinsert       = table.insert
local tsort         = table.sort

local log_err       = logger.err
local log_info      = logger.info
local log_debug     = logger.debug
local check_success = hive.success
local check_failed  = hive.failed
local json_encode   = hive.json_encode
local json_decode   = hive.json_decode
local PeriodTime    = enum("PeriodTime")

local mongo_agent   = hive.get("mongo_agent")
local redis_agent   = hive.get("redis_agent")

local ReliableMsg   = class()
local prop          = property(ReliableMsg)
prop:reader("db_name", "")
prop:reader("table_name", "")
prop:reader("ttl", nil)
prop:reader("is_redis", false) -- 高频通知类用redis,安全保证或长期保存类用mongo

function ReliableMsg:__init(db_name, table_name, due_day, is_redis)
    self.ttl        = (due_day or 1) * PeriodTime.DAY_S
    self.db_name    = db_name
    self.table_name = table_name
    self.is_redis   = is_redis or false
end

function ReliableMsg:build_index()
    if self.is_redis then
        return
    end
    local indexs = {
        { key = { to = 1 }, name = "to", unique = false },
        { key = { uuid = 1 }, name = "uuid", unique = true },
    }
    if self.ttl then
        indexs[#indexs + 1] = { key = { ttl = 1 }, expireAfterSeconds = 0, name = "ttl", unique = false }
    end
    local query    = { self.table_name, indexs }
    local ok, code = mongo_agent:create_indexes(query, nil, self.db_name)
    if check_success(code, ok) then
        log_info("[RmsgMgr][build_index] rmsg table %s build due index success", self.table_name)
    end
end

-- 查询未处理消息列表
function ReliableMsg:list_message(to)
    if self.is_redis then
        return self:list_redis_message(to)
    end
    local query            = { self.table_name, { to = to, deal_time = 0 }, { _id = 0, ttl = 0 }, { time = 1 } }
    local ok, code, result = mongo_agent:find(query, to, self.db_name)
    if check_success(code, ok) then
        return result
    end
end

-- 设置信息为已处理
function ReliableMsg:deal_message(to, uuid)
    log_info("[RmsgMgr][deal_message] deal message: %s", uuid)
    if self.is_redis then
        return self:delete_redis_message(to, uuid)
    end
    local query = { self.table_name, { ["$set"] = { deal_time = hive.now } }, { uuid = uuid } }
    return mongo_agent:update(query, to, self.db_name)
end

-- 删除消息
function ReliableMsg:delete_message(to, uuid)
    log_info("[RmsgMgr][delete_message] delete message: %s", uuid)
    if self.is_redis then
        return self:delete_redis_message(to, uuid)
    end
    return mongo_agent:delete({ self.table_name, { uuid = uuid } }, to, self.db_name)
end

-- 发送消息
function ReliableMsg:send_message(from, to, typ, body, id)
    if self.is_redis then
        return self:send_redis_message(from, to, typ, body, id)
    end
    local uuid = id or hive.new_guid()
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

-- 构建redis key
function ReliableMsg:build_redis_key(to)
    return sformat("RMSG:%s:%s", self.table_name, to)
end

-- 发送redis通知消息
function ReliableMsg:send_redis_message(from, to, typ, body, id)
    local uuid          = id or hive.new_guid()
    local doc           = {
        uuid = uuid,
        from = from, to = to,
        type = typ, body = body,
        time = hive.now,
    }
    local key           = self:build_redis_key(to)
    local value         = json_encode(doc)
    local ok, code, res = redis_agent:execute({ "hset", key, uuid, value })
    if check_failed(code, ok) then
        log_err("[RmsgMgr][send_redis_message] send message failed: uuid:%s, from:%s, to:%s, doc:%s,code:%s,res:%s",
                uuid, from, to, doc, code, res)
        return false
    else
        log_info("[RmsgMgr][send_redis_message] send message succeed: uuid:%s, from:%s, to:%s, type:%s", uuid, from, to, typ)
    end
    --设置过期ttl
    redis_agent:execute({ "expire", key, self.ttl })

    return true
end

-- 删除redis消息
function ReliableMsg:delete_redis_message(to, uuid)
    local key           = self:build_redis_key(to)
    local ok, code, res = redis_agent:execute({ "hdel", key, uuid })
    if check_failed(code, ok) then
        log_err("[RmsgMgr][delete_redis_message] delete message failed [%s]:uuid:%s,to:%s,res:%s", self.table_name, uuid, to, res)
        return false
    else
        log_debug("[RmsgMgr][delete_redis_message] delete message succeed [%s]: uuid:%s,to:%s,res:%s", self.table_name, uuid, to, res)
    end
    return true
end

function ReliableMsg:list_redis_message(to)
    local list_message  = {}
    local key           = self:build_redis_key(to)
    local ok, code, res = redis_agent:execute({ "hgetall", key })
    if check_failed(code, ok) then
        log_err("[RmsgMgr][list_redis_message] get message failed:%s,to:%s,res:%s", self.table_name, to, res)
        return list_message
    else
        log_debug("[RmsgMgr][list_redis_message] get message succeed:%s,to:%s,res:%s", self.table_name, to, res)
        for uuid, value in pairs(res) do
            local msg = json_decode(value)
            tinsert(list_message, msg)
        end
        --时间排序
        tsort(list_message, function(a, b)
            return a.time < b.time
        end)
    end
    return list_message
end

return ReliableMsg