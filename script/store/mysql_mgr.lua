--mysql_mgr.lua
local sformat      = string.format
local KernCode     = enum("KernCode")
local SUCCESS      = KernCode.SUCCESS
local MYSQL_FAILED = KernCode.MYSQL_FAILED
local log_err      = logger.err
local event_mgr    = hive.get("event_mgr")
local config_mgr   = hive.get("config_mgr")

local MysqlMgr     = singleton()
local prop         = property(MysqlMgr)
prop:accessor("mysql_dbs", {})      -- mysql_dbs
prop:accessor("default_db", nil)    -- default_db

function MysqlMgr:__init()
    self:setup()
    -- 注册事件
    event_mgr:add_listener(self, "mysql_execute", "execute")
end

--初始化
function MysqlMgr:setup()
    local MysqlDB  = import("driver/mysql.lua")
    local database = config_mgr:init_table("database", "name")
    for _, conf in database:iterator() do
        local drivers = environ.driver(conf.url)
        if drivers and #drivers > 0 then
            local dconf = drivers[1]
            if dconf.driver == "mysql" then
                local mysql_db          = MysqlDB(dconf)
                self.mysql_dbs[conf.name] = mysql_db
                if conf.default then
                    self.default_db = mysql_db
                end
            end
        end
    end
end

--查找mysql db
function MysqlMgr:get_db(db_name)
    if not db_name or db_name == "default" then
        return self.default_db
    end
    return self.mysql_dbs[db_name]
end

function MysqlMgr:execute(db_name, sql)
    local mysqldb = self:get_db(db_name)
    if mysqldb then
        local ok, res_oe = mysqldb:query(sql)
        if not ok then
            log_err("[MysqlMgr][execute] execute %s failed, because: %s", sql, res_oe)
        end
        return ok and SUCCESS or MYSQL_FAILED, res_oe
    end
    return MYSQL_FAILED, sformat("mysql db [%s] not exist", db_name)
end

hive.mysql_mgr = MysqlMgr()

return MysqlMgr
