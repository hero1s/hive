--lmdb.lua
local lmdb         = require("lmdb")
local log_info     = logger.info
local sformat      = string.format
local xpcall_ret   = hive.xpcall_ret
local update_mgr   = hive.get("update_mgr")

local MDB_SUCCESS  = lmdb.MDB_CODE.MDB_SUCCESS
local MDB_NOTFOUND = lmdb.MDB_CODE.MDB_NOTFOUND

local MDB_NOSUBDIR = lmdb.MDB_ENV_FLAG.MDB_NOSUBDIR

local MDB_FIRST    = lmdb.MDB_CUR_OP.MDB_FIRST
local MDB_NEXT     = lmdb.MDB_CUR_OP.MDB_NEXT
local MDB_SET      = lmdb.MDB_CUR_OP.MDB_SET

local LMDB_PATH    = environ.get("HIVE_LMDB_PATH", "./lmdb/")

local Lmdb         = class()
local prop         = property(Lmdb)
prop:reader("driver", nil)
prop:reader("dbname", nil)
prop:reader("jcodec", nil)

function Lmdb:__init()
    stdfs.mkdir(LMDB_PATH)
    update_mgr:attach_quit(self)
end

function Lmdb:__release()
    self:close()
end

function Lmdb:on_quit()
    self:close()
end

function Lmdb:close()
    if self.driver then
        self.driver.close()
        self.driver = nil
        log_info("[Lmdb][close] close lmdb {}", self.dbname)
    end
end

function Lmdb:open(name, dbname)
    if not self.driver then
        local driver = lmdb.create()
        local jcodec = json.jsoncodec()
        driver.set_max_dbs(128)
        driver.set_codec(jcodec)
        self.driver = driver
        self.jcodec = jcodec
        self.dbname = dbname
        local rc    = driver.open(sformat("%s%s.mdb", LMDB_PATH, name), MDB_NOSUBDIR, tonumber("0644", 8))
        log_info("[Lmdb][open] open lmdb {}:{}!", name, rc)
    end
end

function Lmdb:puts(objects, dbname)
    local ok, res = xpcall_ret(self.driver.batch_put, "Lmdb:puts:%s", objects, dbname or self.dbname)
    if ok and res == MDB_SUCCESS then
        return true
    end
    return false
end

function Lmdb:put(key, value, dbname)
    local ok, res = xpcall_ret(self.driver.quick_put, "Lmdb:put:%s", key, value, dbname or self.dbname)
    if ok and res == MDB_SUCCESS then
        return true
    end
    return false
end

function Lmdb:get(key, dbname)
    local ok, data, rc = xpcall_ret(self.driver.quick_get, "Lmdb:get:%s", key, dbname or self.dbname)
    if ok and (rc == MDB_NOTFOUND or rc == MDB_SUCCESS) then
        return data, true
    end
    return nil, false
end

function Lmdb:gets(keys, dbname)
    local ok, res, rc = xpcall_ret(self.driver.batch_get, "Lmdb:gets:%s", keys, dbname or self.dbname)
    if ok and (rc == MDB_NOTFOUND or rc == MDB_SUCCESS) then
        return res, true
    end
    return nil, false
end

function Lmdb:del(key, dbname)
    local ok, rc = xpcall_ret(self.driver.quick_del, "Lmdb:del:%s", key, dbname or self.dbname)
    return ok and (rc == MDB_NOTFOUND or rc == MDB_SUCCESS) or false
end

function Lmdb:dels(keys, dbname)
    local ok, rc = xpcall_ret(self.driver.batch_del, "Lmdb:dels:%s", keys, dbname or self.dbname)
    return ok and (rc == MDB_NOTFOUND or rc == MDB_SUCCESS) or false
end

function Lmdb:drop(dbname)
    local ok, rc = xpcall_ret(self.driver.quick_drop, "Lmdb:drop:%s", dbname or self.dbname)
    return ok and (rc == MDB_NOTFOUND or rc == MDB_SUCCESS) or false
end

--迭代器
function Lmdb:iter(dbname, key)
    local flag   = nil
    local driver = self.driver
    driver.cursor_open(dbname or self.dbname)
    local function iter()
        local _, k, v
        if not flag then
            flag    = MDB_NEXT
            _, k, v = driver.cursor_get(key, key and MDB_SET or MDB_FIRST)
        else
            _, k, v = driver.cursor_get(key, flag)
        end
        if not v then
            driver.cursor_close()
        end
        return k, v
    end
    return iter
end

return Lmdb
