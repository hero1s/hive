--clickhouse_mgr.lua
local log_err       = logger.err

local KernCode      = enum("KernCode")
local SUCCESS       = KernCode.SUCCESS
local MYSQL_FAILED  = KernCode.MYSQL_FAILED

local event_mgr     = hive.get("event_mgr")
local config_mgr    = hive.get("config_mgr")

local ClickHouseMgr = singleton()
local prop = property(ClickHouseMgr)
prop:accessor("clickhouse_dbs", {})     -- clickhouse_dbs
prop:accessor("default_db", nil)        -- default_db

function ClickHouseMgr:__init()
    self:setup()
    -- 注册事件
    event_mgr:add_listener(self, "clickhouse_execute", "execute")
end

--初始化
function ClickHouseMgr:setup()
    local MysqlDB = import("driver/mysql.lua")
    local database = config_mgr:init_table("database", "name")
    for _, conf in database:iterator() do
        local drivers = environ.driver(conf.url)
        if drivers and #drivers > 0 then
            local dconf = drivers[1]
            if dconf.driver == "clickhouse" then
                local clickhouse_db = MysqlDB(dconf)
                self.clickhouse_dbs[conf.name] = clickhouse_db
                if conf.default then
                    self.default_db = clickhouse_db
                end
            end
        end
    end
end

--查找clickhouse db
function ClickHouseMgr:get_db(db_name)
    if not db_name or db_name == "default" then
        return self.default_db
    end
    return self.clickhouse_dbs[db_name]
end

function ClickHouseMgr:execute(db_name, sql)
    local clickhousedb = self:get_db(db_name)
    if clickhousedb then
        local ok, res_oe = clickhousedb:query(sql)
        if not ok then
            log_err("[ClickHouseMgr][execute] execute %s failed, because: %s", sql, res_oe)
        end
        return ok and SUCCESS or MYSQL_FAILED, res_oe
    end
    return MYSQL_FAILED, "clickhouse db not exist"
end

hive.clickhouse = ClickHouseMgr()

return ClickHouseMgr
