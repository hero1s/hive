--redis_mgr.lua
local sformat      = string.format
local tpack        = table.pack
local log_err      = logger.err
local KernCode     = enum("KernCode")
local SUCCESS      = KernCode.SUCCESS
local REDIS_FAILED = KernCode.REDIS_FAILED

local event_mgr    = hive.get("event_mgr")
local config_mgr   = hive.get("config_mgr")

local RedisMgr     = singleton()
local prop         = property(RedisMgr)
prop:accessor("redis_dbs", {})      -- redis_dbs
prop:accessor("default_db", nil)    -- default_db
prop:reader("db_counters", {})
prop:reader("qps_warn_avg", 1000)

function RedisMgr:__init()
    self:setup()
    -- 注册事件
    event_mgr:add_listener(self, "rpc_redis_execute", "execute")
end

--初始化
function RedisMgr:setup()
    local RedisDB  = import("driver/redis.lua")
    local database = config_mgr:init_table("database", "name")
    for _, conf in database:iterator() do
        local dconf = environ.driver(conf.url)
        if dconf then
            if dconf.driver == "redis" then
                local redis_db              = RedisDB(dconf)
                self.redis_dbs[conf.name]   = redis_db
                self.db_counters[conf.name] = hive.make_sampling(sformat("redis [%s] qps", conf.name), nil, self.qps_warn_avg)
                if conf.default then
                    self.default_db = redis_db
                end
            end
        end
    end
    self.db_counters["default"] = hive.make_sampling(sformat("redis [default] qps"), nil, self.qps_warn_avg)
end

--查找redis db
function RedisMgr:get_db(db_name)
    if not db_name or db_name == "default" then
        return self.default_db
    end
    return self.redis_dbs[db_name]
end

function RedisMgr:execute(db_name, cmd, ...)
    local redisdb = self:get_db(db_name)
    if redisdb then
        local ok, res_oe = redisdb:execute(cmd, ...)
        if not ok then
            log_err("[RedisMgr][execute] execute {} ({}) failed, because: {}", cmd, tpack(...), res_oe)
        end
        self.db_counters[db_name or "default"]:count_increase()
        return ok and SUCCESS or REDIS_FAILED, res_oe
    end
    return REDIS_FAILED, sformat("redis db [%s] not exist", db_name)
end

hive.redis_mgr = RedisMgr()

return RedisMgr
