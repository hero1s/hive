local lmdb         = require("lmdb")
local log_debug    = logger.debug
local jsoncodec    = json.jsoncodec

local MDB_CREATE   = lmdb.MDB_DBI_FLAG.MDB_CREATE
local MDB_NOSUBDIR = lmdb.MDB_ENV_FLAG.MDB_NOSUBDIR
local MDB_NEXT     = lmdb.MDB_CUR_OP.MDB_NEXT
local MDB_SET      = lmdb.MDB_CUR_OP.MDB_SET

local driver       = lmdb.create()
local jcodec       = jsoncodec()

driver.set_max_dbs(10)
driver.set_codec(jcodec)
driver.open("./lmdb/xxx.mdb", MDB_NOSUBDIR, 0644)

driver.begin_txn("test", MDB_CREATE)
local a = driver.put("abc1", { a = 123 })
local b = driver.put("abc2", "234")
local c = driver.put("abc3", "235")
local d = driver.put("abc4", "235")
log_debug("put: {}-{}-{}-{}", a, b, c, d)
driver.commit_txn()

driver.begin_txn("test")
a = driver.get("abc1")
b = driver.get("abc2")
log_debug("get: {}-{}", a, b)
a = driver.get("abc4")
b = driver.get("abc5")
log_debug("get: {}-{}", a, b)
driver.commit_txn()

driver.cursor_open("test")
local v, k, r = driver.cursor_get("abc1", MDB_SET)
while v do
    log_debug("cursor: {}-{}-{}", v, k, r)
    v, k, r = driver.cursor_get(0, MDB_NEXT)
end
driver.cursor_close()

a = driver.easy_put("abc4", { a = 123 })
b = driver.easy_put("abc5", "235")
log_debug("easy_put: {}-{}", a, b)
a, c = driver.easy_get("abc1")
b, d = driver.easy_get("abc2")
log_debug("easy_get: {}-{}-{}-{}", a, b, c, d)
a, c = driver.easy_get("abc4")
b, d = driver.easy_get("abc5")
log_debug("easy_get: {}-{}-{}-{}", a, b, c, d)
a = driver.easy_del("abc5")
b = driver.easy_del("abc4")
c = driver.easy_get("abc4")
d = driver.easy_get("abc5")
log_debug("easy_del_get: {}-{}-{}-{}", a, b, c, d)

local objects = { a = true, b = 3, c = 3 }
local s       = driver.batch_put(objects, "test")
log_debug("batch_put: {}", s)

local x = driver.batch_get({ "a", "b", "c", "d" }, "test")
log_debug("batch_get: {}", x)

local g = driver.batch_del({ "a", "b", "c", "d" }, "test")
log_debug("batch_del: {}", g)

local y = driver.batch_get({ "a", "b", "c", "d" }, "test")
log_debug("batch_get: {}", y)

local LMDB = import("driver/lmdb.lua")
local db   = LMDB("abcd", "aaa")

local cc   = db:put(11, "abc")
local c2   = db:put("a", "abc")

local gv   = db:get("11")

log_debug("put: {}-{} get: {}", cc, c2, gv)

cc = db:puts({ 234, 3, 5 })
log_debug("puts: {}", cc)

local gv2, e = db:get(2)
log_debug("get: {} code: {}", gv2, e)

local gs = db:gets(1, 2, 3, 11)
log_debug("gets: {}", gs)

for _k, _v in db:iter() do
    log_debug("iter: {}-{}", _k, _v)
end

local ee = db:del(2)
log_debug("del: {}", ee)

gv2, e = db:get(2)
log_debug("get: {} code: {}", gv2, e)

ee = db:dels(1, 2)
log_debug("dels: {}", ee)

for _k, _v in db:iter() do
    log_debug("iter: {}-{}", _k, _v)
end
