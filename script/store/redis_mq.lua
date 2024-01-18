--redis_mq.lua
import("agent/redis_agent.lua")

local log_err       = logger.err
local log_info      = logger.info
local log_debug     = logger.debug
local sformat       = string.format
local check_success = hive.success

local redis_agent   = hive.get("redis_agent")
local NAMESPACE     = environ.get("HIVE_NAMESPACE")

local RedisMQ       = class()
local prop          = property(RedisMQ)
prop:reader("coll_name", "")    -- coll_name
prop:reader("prefix", nil)      -- prefix

function RedisMQ:__init()
end

function RedisMQ:setup(coll_name)
    self.coll_name = coll_name
    self.prefix    = sformat("RELIABLE:%s:%s", NAMESPACE, coll_name)
    log_info("[RedisMQ][setup] init rmsg coll: {}", coll_name)
end

-- 获取消息长度
function RedisMQ:len_message(target_id)
    local zset_name        = sformat("%s:%s", self.prefix, target_id)
    local ok, code, result = redis_agent:execute({ "ZCARD", zset_name })
    if check_success(code, ok) then
        return result
    end
    return 0
end

-- 查询未处理消息列表
function RedisMQ:list_message(target_id)
    local zset_name        = sformat("%s:%s", self.prefix, target_id)
    local ok, code, result = redis_agent:execute({ "ZRANGE", zset_name, 0, -1 }, target_id)
    if check_success(code, ok) then
        return result
    end
    return {}
end

-- 删除消息
function RedisMQ:delete_message(target_id, timestamp)
    log_info("[RedisMQ][delete_message] delete message: {}-{}", target_id, timestamp)
    local zset_name = sformat("%s:%s", self.prefix, target_id)
    return redis_agent:execute({ "ZREMRANGEBYSCORE", zset_name, 0, timestamp }, target_id)
end

-- 发送消息
function RedisMQ:send_message(target_id, event, args, ttl)
    local timestamp = hive.now_ms
    local doc       = { args = args, event = event, time = timestamp }
    local zset_name = sformat("%s:%s", self.prefix, target_id)
    local ok, code  = redis_agent:execute({ "ZADD", zset_name, timestamp, doc }, target_id)
    if check_success(code, ok) then
        if ttl then
            redis_agent:execute({ "EXPIRE", zset_name, ttl }, target_id)
        end
        log_debug("[RedisMQ][send_message] send message succeed: {}, {}", target_id, doc)
        return true
    end
    log_err("[RedisMQ][send_message] send message failed: {}, {}", target_id, doc)
    return false
end

return RedisMQ
