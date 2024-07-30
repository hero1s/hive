-- 限流器
local sformat = string.format
local log_err = logger.err
local hdefer  = hive.defer

local Limiter = class()
local prop    = property(Limiter)

prop:reader("name", "")
prop:reader("warn_size", 1000)   -- 警告频率
prop:reader("refuse_size", 1000) -- 拒绝服务阈值
prop:reader("qps_warn", 1000)    -- qps 告警阈值
prop:reader("cur_req", 0)
prop:reader("qps_counter", nil)

function Limiter:__init(name, warn_size, refuse_size, qps_warn)
    self.name        = name
    self.warn_size   = warn_size or 1000
    self.refuse_size = refuse_size or 1000
    self.qps_warn    = qps_warn or 1000
    self.qps_counter = hive.make_sampling(sformat("limiter[%s] qps", self.name), nil, self.qps_warn)
end

function Limiter:incr()
    if self.cur_req > self.refuse_size then
        log_err("[Limiter][incr] name:%s,cur:%s > refuse:%s", self.name, self.cur_req, self.refuse_size)
        return false
    end
    if self.cur_req > self.warn_size then
        log_err("[Limiter][incr] name:%s,cur:%s > warn:%s", self.name, self.cur_req, self.warn_size)
    end
    self.cur_req = self.cur_req + 1
    self.qps_counter:count_increase()
    return true
end

function Limiter:decr()
    self.cur_req = self.cur_req - 1
end

function Limiter:allow()
    local allow = self:incr()
    if not allow then
        return nil
    end
    return hdefer(function()
        self:decr()
    end)
end

return Limiter
