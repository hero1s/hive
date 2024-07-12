import("agent/mongo_agent.lua")
local QueueFIFO     = import("container/queue_fifo.lua")
local bdate         = bson.date
local lnow_ms       = timer.now_ms
local tinsert       = table.insert
local log_err       = logger.err
local log_info      = logger.info
local check_success = hive.success
local check_failed  = hive.failed
local PeriodTime    = enum("PeriodTime")
local mceil         = math.ceil

local mongo_agent   = hive.get("mongo_agent")
local thread_mgr    = hive.get("thread_mgr")
local update_mgr    = hive.get("update_mgr")

local ReliableMsg   = class()
local prop          = property(ReliableMsg)
prop:reader("db_name", "")
prop:reader("table_name", "")
prop:reader("ttl", nil)

function ReliableMsg:__init(db_name, table_name, due_day)
    self.ttl         = mceil((due_day or 1) * PeriodTime.DAY_S - 0.5)
    self.db_name     = db_name
    self.table_name  = table_name
    self.retry_queue = QueueFIFO(20000)

    update_mgr:attach_minute(self)
end

function ReliableMsg:generate_index(sharding)
    local indexs = {
        { key = { uuid = 1 }, name = "uuid", unique = (not sharding), background = true },
    }
    if not sharding then
        tinsert(indexs, { key = { to = 1 }, name = "to", unique = false, background = true })
    end
    if self.ttl then
        tinsert(indexs, { key = { ttl = 1 }, expireAfterSeconds = 0, name = "ttl", unique = false, background = true })
    end
    return indexs
end

function ReliableMsg:build_index(sharding, rebuild)
    local indexs = self:generate_index(sharding)
    for _, index in pairs(indexs) do
        if not sharding or index.name ~= "to" then
            mongo_agent:rebuild_create_index(index, self.table_name, self.db_name, rebuild)
        end
    end
end

function ReliableMsg:check_indexes(sharding)
    local indexs  = self:generate_index(sharding)
    local success = true
    local miss    = {}
    for _, index in ipairs(indexs) do
        if not mongo_agent:check_indexes(index, self.table_name, self.db_name, sharding) then
            success = false
            tinsert(miss, { db = self.db_name, co = self.table_name, index = index })
        end
    end
    return success, miss
end

function ReliableMsg:len_message(to)
    local query            = { self.table_name, { to = to } }
    local ok, code, result = mongo_agent:count(query, to, self.db_name)
    if check_success(code, ok) then
        return result
    end
    return 0
end

-- 查询未处理消息列表
function ReliableMsg:list_message(to, page_size)
    local query            = { self.table_name, { to = to, deal_time = 0 }, { _id = 0, ttl = 0 }, { time = 1 } }
    local ok, code, result = mongo_agent:find(query, to, self.db_name, page_size)
    if check_success(code, ok) then
        return result
    end
    return {}
end

-- 设置信息为已处理
function ReliableMsg:deal_message(to, timestamp)
    log_info("[ReliableMsg][deal_message] message:{}, {},{}", self.table_name, to, timestamp)
    local selector = { to = to, time = { ["$lte"] = timestamp } }
    local query    = { self.table_name, { ["$set"] = { deal_time = hive.now } }, selector }
    return mongo_agent:update(query, to, self.db_name)
end

function ReliableMsg:deal_message_by_uuid(uuid, to)
    log_info("[ReliableMsg][deal_message_by_uuid] message:{},{}", self.table_name, uuid)
    local query = { self.table_name, { ["$set"] = { deal_time = hive.now } }, { uuid = uuid, to = to } }
    return mongo_agent:update(query, hive.id, self.db_name)
end

-- 删除消息
function ReliableMsg:delete_message(to, timestamp)
    log_info("[ReliableMsg][delete_message] delete {} message: {}", self.table_name, to)
    local selector = { to = to, time = { ["$lte"] = timestamp } }
    return mongo_agent:delete({ self.table_name, selector }, hive.id, self.db_name)
end

function ReliableMsg:delete_message_by_uuid(uuid, to)
    log_info("[ReliableMsg][delete_message_by_uuid] delete message: {}", uuid)
    return mongo_agent:delete({ self.table_name, { uuid = uuid, to = to }, true }, hive.id, self.db_name)
end

function ReliableMsg:delete_message_from_to(from, to, type, onlyone)
    log_info("[ReliableMsg][delete_message_from_to] delete message from:{},to:{},type:{}", from, to, type)
    local selector = { from = from, to = to }
    if type then
        selector["type"] = type
    end
    return mongo_agent:delete({ self.table_name, selector, onlyone }, hive.id, self.db_name)
end

-- 发送消息
function ReliableMsg:send_message(from, to, body, typ, id, retry)
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
        log_err("[ReliableMsg][send_message] send message failed: uuid:{}, from:{}, to:{}, doc:{},code:{},res:{}",
                uuid, from, to, doc, code, res)
        if retry then
            self.retry_queue:push(doc)
        end
        return false
    else
        log_info("[ReliableMsg][send_message] send message succeed: uuid:{}, from:{}, to:{}, type:{}", uuid, from, to, typ)
    end
    return true
end

function ReliableMsg:retry_send_message(msg)
    local ok, code = mongo_agent:update({ self.table_name, msg, { uuid = msg.uuid, to = msg.to }, true }, msg.to, self.db_name)
    if check_failed(code, ok) then
        return false
    end
    log_info("[ReliableMsg][retry_send_message] succeed: uuid:%s, from:%s, to:%s, type:%s", msg.uuid, msg.from, msg.to, msg.type)
    return true
end

function ReliableMsg:on_minute()
    thread_mgr:entry(self:address(), function()
        while self.retry_queue:size() > 0 do
            local msg = self.retry_queue:head()
            if msg then
                if self:retry_send_message(msg) then
                    self.retry_queue:pop()
                else
                    break
                end
            end
        end
    end)
end

return ReliableMsg
