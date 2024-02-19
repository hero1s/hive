--mysql_mgr.lua
local log_err      = logger.err
local mrandom      = math_ext.random

local event_mgr    = hive.get("event_mgr")
local config_mgr   = hive.get("config_mgr")

local SUCCESS      = hive.enum("KernCode", "SUCCESS")
local MYSQL_FAILED = hive.enum("KernCode", "MYSQL_FAILED")

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
    local MysqlDB  = import("driver/mysql.lua")
    local database = config_mgr:init_table("database", "name")
    for _, conf in database:iterator() do
        local dconf = environ.driver(conf.url)
        if dconf then
            if dconf.driver == "mysql" then
                local mysql_db            = MysqlDB(dconf)
                self.mysql_dbs[conf.name] = mysql_db
                if conf.default then
                    self.default_db = mysql_db
                end
            end
        end
    end
end

--查找mysql db
function MysqlMgr:get_db(db_name, hash_key)
    local mysqldb
    if not db_name or db_name == "default" then
        mysqldb = self.default_db
    else
        mysqldb = self.mysql_dbs[db_name]
    end
    if mysqldb and mysqldb:set_executer(hash_key or mrandom()) then
        return mysqldb
    end
    return nil
end

function MysqlMgr:query(db_name, primary_id, sql)
    local mysqldb = self:get_db(db_name, primary_id)
    if mysqldb then
        local ok, res_oe = mysqldb:query(sql)
        if not ok then
            log_err("[MysqlMgr][query] query {} failed, because: {}", sql, res_oe)
        end
        return ok and SUCCESS or MYSQL_FAILED, res_oe
    end
    return MYSQL_FAILED, "mysql db not exist"
end

function MysqlMgr:execute(db_name, primary_id, stmt, ...)
    local mysqldb = self:get_db(db_name, primary_id)
    if mysqldb then
        local ok, res_oe = mysqldb:execute(stmt, ...)
        if not ok then
            log_err("[MysqlMgr][execute] execute {} failed, because: {}", stmt, res_oe)
        end
        return ok and SUCCESS or MYSQL_FAILED, res_oe
    end
    return MYSQL_FAILED, "mysql db not exist"
end

function MysqlMgr:prepare(db_name, primary_id, sql)
    local mysqldb = self:get_db(db_name, primary_id)
    if mysqldb then
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
