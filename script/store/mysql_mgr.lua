--mysql_mgr.lua
local log_err      = logger.err

local event_mgr    = hive.get("event_mgr")

local SUCCESS      = hive.enum("KernCode", "SUCCESS")
local MYSQL_FAILED = hive.enum("KernCode", "MYSQL_FAILED")

local MAIN_DBID    = environ.number("HIVE_DB_MAIN_ID")

local MysqlMgr     = singleton()
local prop         = property(MysqlMgr)
prop:reader("mysql_dbs", {})    -- mysql_dbs

function MysqlMgr:__init()
    self:setup()
    -- 注册事件
    event_mgr:add_listener(self, "rpc_mysql_query", "query")
    event_mgr:add_listener(self, "rpc_mysql_prepare", "prepare")
    event_mgr:add_listener(self, "rpc_mysql_execute", "execute")
end

--初始化
function MysqlMgr:setup()
    local MysqlDB = import("driver/mysql.lua")
    local drivers = environ.driver("HIVE_MYSQL_URLS")
    for i, conf in ipairs(drivers) do
        local mysql_db    = MysqlDB(conf, i)
        self.mysql_dbs[i] = mysql_db
    end
end

--查找mysql db
function MysqlMgr:get_db(db_id)
    return self.mysql_dbs[db_id or MAIN_DBID]
end

function MysqlMgr:query(db_id, primary_id, sql)
    local mysqldb = self:get_db(db_id)
    if mysqldb and mysqldb:set_executer(primary_id) then
        local ok, res_oe = mysqldb:query(sql)
        if not ok then
            log_err("[MysqlMgr][query] query {} failed, because: {}", sql, res_oe)
        end
        return ok and SUCCESS or MYSQL_FAILED, res_oe
    end
    return MYSQL_FAILED, "mysql db not exist"
end

function MysqlMgr:execute(db_id, primary_id, stmt, ...)
    local mysqldb = self:get_db(db_id)
    if mysqldb and mysqldb:set_executer(primary_id) then
        local ok, res_oe = mysqldb:execute(stmt, ...)
        if not ok then
            log_err("[MysqlMgr][execute] execute {} failed, because: {}", stmt, res_oe)
        end
        return ok and SUCCESS or MYSQL_FAILED, res_oe
    end
    return MYSQL_FAILED, "mysql db not exist"
end

function MysqlMgr:prepare(db_id, sql)
    local mysqldb = self:get_db(db_id)
    if mysqldb and mysqldb:set_executer() then
        local ok, res_oe = mysqldb:prepare(sql)
        if not ok then
            log_err("[MysqlMgr][prepare] prepare {} failed, because: {}", sql, res_oe)
        end
        return ok and SUCCESS or MYSQL_FAILED, res_oe
    end
    return MYSQL_FAILED, "mysql db not exist"
end

hive.mysql_mgr = MysqlMgr()

return MysqlMgr
