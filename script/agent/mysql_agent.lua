--mysql_agent.lua
local sformat     = string.format
local assert      = assert
local readfile    = io_ext.readfile
local KernCode    = enum("KernCode")
local router_mgr  = hive.load("router_mgr")
local scheduler   = hive.load("scheduler")
local PARAM_ERROR = hive.enum("KernCode", "PARAM_ERROR")

local MysqlAgent  = singleton()
local prop        = property(MysqlAgent)
prop:reader("service", "mysql")
prop:reader("local_run", false) --本地线程服务

function MysqlAgent:__init()
end

function MysqlAgent:start_local_run()
    if self.local_run then
        return
    end
    --启动代理线程
    self.local_run = scheduler:startup(self.service, "worker.mysql")
end

function MysqlAgent:gen_condition_str(conditions)
    local str = ""
    for key, value in pairs(conditions) do
        if str ~= "" then
            str = str .. " and"
        end
        local value_str = (type(value) == 'string') and ("'" .. value .. "'") or value
        str             = str .. " `" .. key .. "` = " .. value_str
    end
    return str
end

function MysqlAgent:gen_update_values_str(columns, inc)
    local str = ""
    for key, value in pairs(columns) do
        if str ~= "" then
            str = str .. ","
        end
        local value_str = (type(value) == 'string') and ("'" .. value .. "'") or value
        if inc then
            str = str .. " `" .. key .. "` = `" .. key .. "` + " .. value_str
        else
            str = str .. " `" .. key .. "` = " .. value_str
        end
    end
    return str
end

function MysqlAgent:gen_insert_str(columns)
    local keys   = ""
    local values = ""
    for key, value in pairs(columns) do
        if keys ~= "" then
            keys = keys .. ","
        end
        keys = keys .. "`" .. key .. "`"
        if values ~= "" then
            values = values .. ","
        end
        local value_str = (type(value) == 'string') and ("'" .. value .. "'") or value
        values          = values .. value_str
    end

    local str = sformat("(%s) values (%s)", keys, values)
    return str
end

function MysqlAgent:gen_query_fields_str(fields)
    local str = ""
    for _, key in ipairs(fields) do
        if str ~= "" then
            str = str .. ","
        end
        str = str .. " `" .. key .. "` "
    end
    return str
end

-- 更新
function MysqlAgent:update(db_name, table_name, columns, conditions)
    if not next(columns) or not next(conditions) then
        return false, PARAM_ERROR
    end
    local sql = sformat("update `%s` set %s where %s;", table_name, self:gen_update_values_str(columns), self:gen_condition_str(conditions))
    return self:execute(sql, db_name)
end

-- 增量更新
function MysqlAgent:inc_update(db_name, table_name, columns, conditions)
    if not next(columns) or not next(conditions) then
        return false, PARAM_ERROR
    end
    local sql = sformat("update `%s` set %s where %s;", table_name, self:gen_update_values_str(columns, true), self:gen_condition_str(conditions))
    return self:execute(sql, db_name)
end

-- 插入
function MysqlAgent:insert(db_name, table_name, columns)
    if not next(columns) then
        return false, PARAM_ERROR
    end
    local sql = sformat("insert into `%s` %s;", table_name, self:gen_insert_str(columns))
    return self:execute(sql, db_name)
end

-- 重复插入(存在则更新，不存在则插入)
function MysqlAgent:insert_or_update(db_name, table_name, columns)
    if not next(columns) then
        return false, PARAM_ERROR
    end
    local sql = sformat("insert into `%s` %s on duplicate key update %s;", table_name, self:gen_insert_str(columns), self:gen_update_values_str(columns))
    return self:execute(sql, db_name)
end

-- 替换
function MysqlAgent:replace(db_name, table_name, columns)
    if not next(columns) then
        return false, PARAM_ERROR
    end
    local sql = sformat("replace into `%s` %s;", table_name, self:gen_insert_str(columns))
    return self:execute(sql, db_name)
end

-- 查询
-- order_type: desc asc
-- limit_cnt: 查询的数量 offset[可选] 偏移量
function MysqlAgent:query(db_name, table_name, conditions, fields, group_by_key, order_by_key, order_type, limit_cnt, offset)
    local query_field_str = "*"
    if fields and #fields > 0 then
        query_field_str = self:gen_query_fields_str(fields)
    end

    if conditions and next(conditions) then
        -- 带条件查询
        local sql = sformat("select %s from `%s` where %s", query_field_str, table_name, self:gen_condition_str(conditions))

        if group_by_key then
            sql = sql .. " group by `" .. group_by_key .. "`"
        end

        if order_by_key then
            sql = sql .. " order by `" .. order_by_key .. "` " .. order_type
        end

        if limit_cnt then
            if not offset then
                sql = sql .. " limit " .. limit_cnt
            else
                sql = sql .. " limit " .. offset .. "," .. limit_cnt
            end
        end

        return self:execute(sql, db_name)
    else
        -- 不带条件查询
        local sql = sformat("select %s from `%s`;", query_field_str, table_name)
        return self:execute(sql, db_name)
    end
end

-- 删除(带条件的删除)
function MysqlAgent:delete(db_name, table_name, conditions)
    assert(next(conditions) ~= nil)
    local sql = sformat("delete from `%s` where %s;", table_name, self:gen_condition_str(conditions))
    return self:execute(sql, db_name)
end

-- 清空整张表
function MysqlAgent:truncate(db_name, table_name)
    if not table_name or table_name == "" then
        return false, PARAM_ERROR
    end
    local sql = sformat("truncate table `%s`;", table_name)
    return self:execute(sql, db_name)
end

-- 根据旧表建新表
function MysqlAgent:create_table(db_name, new_table_name, old_table_name)
    local sql = sformat("create table %s like %s", new_table_name, old_table_name)
    return self:execute(sql, db_name)
end

-- 删表
function MysqlAgent:drop_table(db_name, table_name)
    local sql = sformat("drop table if exists %s", table_name)
    return self:execute(sql, db_name)
end

-- 执行sql文件
function MysqlAgent:execute_sql_file(db_name, file_name)
    local sql = readfile(file_name)
    return self:execute(sql, db_name)
end

--发送数据库请求
function MysqlAgent:execute(sql, db_name, hash_key)
    if self.local_run then
        return scheduler:call(self.service, "mysql_execute", db_name or "default", sql)
    end
    if router_mgr then
        return router_mgr:call_dbsvr_hash(hash_key or hive.id, "mysql_execute", db_name or "default", sql)
    end
    return false, KernCode.FAILED, "init not right"
end

------------------------------------------------------------------
hive.mysql_agent = MysqlAgent()

return MysqlAgent
