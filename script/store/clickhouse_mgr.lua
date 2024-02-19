--clickhouse_mgr.lua
local log_err       = logger.err
local mrandom       = math_ext.random
local event_mgr     = hive.get("event_mgr")
local config_mgr    = hive.get("config_mgr")

local SUCCESS       = hive.enum("KernCode", "SUCCESS")
local MYSQL_FAILED  = hive.enum("KernCode", "MYSQL_FAILED")

local ClickHouseMgr = singleton()
local prop          = property(ClickHouseMgr)
prop:reader("clickhouse_dbs", {})   -- clickhouse_dbs

function ClickHouseMgr:__init()
    self:setup()
    -- 注册事件
    event_mgr:add_listener(self, "rpc_clickhouse_query", "query")
    event_mgr:add_listener(self, "rpc_clickhouse_prepare", "prepare")
    event_mgr:add_listener(self, "rpc_clickhouse_execute", "execute")
end

--初始化
function ClickHouseMgr:setup()
    local MysqlDB  = import("driver/mysql.lua")
    local database = config_mgr:init_table("database", "name")
    for _, conf in database:iterator() do
        local dconf = environ.driver(conf.url)
        if dconf then
            if dconf.driver == "mysql" then
                local mysql_db                 = MysqlDB(dconf)
                self.clickhouse_dbs[conf.name] = mysql_db
                if conf.default then
                    self.default_db = mysql_db
                end
            end
        end
    end
end

--查找clickhouse db
function ClickHouseMgr:get_db(db_name, hash_key)
    local mysqldb
    if not db_name or db_name == "default" then
        mysqldb = self.default_db
    else
        mysqldb = self.clickhouse_dbs[db_name]
    end
    if mysqldb and mysqldb:set_executer(hash_key or mrandom()) then
        return mysqldb
    end
    return nil
end

function ClickHouseMgr:query(db_name, primary_id, sql)
    local clickhouse_db = self:get_db(db_name, primary_id)
    if clickhouse_db then
        local ok, res_oe = clickhouse_db:query(sql)
        if not ok then
            log_err("[ClickHouseMgr][query] query {} failed, because: {}", sql, res_oe)
        end
        return ok and SUCCESS or MYSQL_FAILED, res_oe
    end
    return MYSQL_FAILED, "clickhouse db not exist"
end

function ClickHouseMgr:execute(db_name, primary_id, stmt, ...)
    local clickhouse_db = self:get_db(db_name, primary_id)
    if clickhouse_db then
        local ok, res_oe = clickhouse_db:execute(stmt, ...)
        if not ok then
            log_err("[ClickHouseMgr][execute] execute {} failed, because: {}", stmt, res_oe)
        end
        return ok and SUCCESS or MYSQL_FAILED, res_oe
    end
    return MYSQL_FAILED, "clickhouse db not exist"
end

function ClickHouseMgr:prepare(db_name, primary_id, sql)
    local clickhouse_db = self:get_db(db_name, primary_id)
    if clickhouse_db and clickhouse_db:set_executer() then
        local ok, res_oe = clickhouse_db:prepare(sql)
        if not ok then
            log_err("[ClickHouseMgr][prepare] prepare {} failed, because: {}", sql, res_oe)
        end
        return ok and SUCCESS or MYSQL_FAILED, res_oe
    end
    return MYSQL_FAILED, "clickhouse db not exist"
end

hive.clickhouse = ClickHouseMgr()

return ClickHouseMgr
