local lmdb         = require("lmdb")
local log_debug    = logger.debug
local jsoncodec    = json.jsoncodec

local MDB_CREATE   = lmdb.MDB_DBI_FLAG.MDB_CREATE
local MDB_NOSUBDIR = lmdb.MDB_ENV_FLAG.MDB_NOSUBDIR
local MDB_FIRST    = lmdb.MDB_CUR_OP.MDB_FIRST
local MDB_NEXT     = lmdb.MDB_CUR_OP.MDB_NEXT
local MDB_SET      = lmdb.MDB_CUR_OP.MDB_SET

local driver       = lmdb.create()
local jcodec       = jsoncodec()
stdfs.mkdir("./lmdb")
driver.set_max_dbs(10)
driver.set_codec(jcodec)
driver.open("./lmdb/xxx.mdb", MDB_NOSUBDIR, 0644)

driver.begin_txn("test", MDB_CREATE)
local a = driver.put("abc1", { a = 123 })
local b = driver.put("abc2", "234")
local c = driver.put("abc3", "235")
local d = driver.put("abc4", "236")
log_debug("put: {}-{}-{}-{}", a, b, c, d)
driver.commit_txn()

driver.begin_txn("test")
for i = 1, 6 do
    local da, rc = driver.get("abc" .. i)
    log_debug("get-{}: {}-{}", i, da, rc)
end
driver.commit_txn()

driver.cursor_open("test")
local r, k, v = driver.cursor_get("abc1", MDB_SET)
while v do
    log_debug("cursor: {}={}->{}", k, v, r)
    r, k, v = driver.cursor_get(0, MDB_NEXT)
end
driver.cursor_close()

a = hive.xpcall_ret(driver.quick_put, "exception call:%s", "abc4", { a = 234, b = 0.0 / 0.0 }, "test")
b = driver.quick_put("abc5", "235", "test")
log_debug("quick_put: {}-{}", a, b)
for i = 1, 6 do
    local da, rc = driver.quick_get("abc" .. i, "test")
    log_debug("quick_get-{}: {}-{}", i, da, rc)
end

b = driver.quick_del("abc4", "test")
a = driver.quick_del("abc5", "test")
log_debug("quick_del: {}-{}", a, b)
for i = 1, 6 do
    local da, rc = driver.quick_get("abc" .. i, "test")
    log_debug("quick_del_get-{}: {}-{}", i, da, rc)
end

local objects = { a = true, b = 3, c = 3 }
local s       = driver.batch_put(objects, "test")
log_debug("batch_put: {}", s)

local x = driver.batch_get({ "a", "b", "c", "d" }, "test")
log_debug("batch_get: {}", x)

local g = driver.batch_del({ "a", "b", "c", "d" }, "test")
log_debug("batch_del: {}", g)

local y = driver.batch_get({ "a", "b", "c", "d" }, "test")
log_debug("batch_get: {}", y)

local dp = driver.quick_drop("test", true)
log_debug("quick_drop: {}", dp)

driver.cursor_open("test")
r, k, v = driver.cursor_get("abc1", MDB_FIRST)
while v do
    log_debug("cursor2: {}={}->{}", k, v, r)
    r, k, v = driver.cursor_get(0, MDB_NEXT)
end
driver.cursor_close()

local LMDB = import("driver/lmdb.lua")
local db   = LMDB()
db:open("abcd", "aaa")

local cc = db:put(11, { a = 123, b = 0.0 / 0.0 })
local c2 = db:put("a", "abc")

local gv = db:get("11")

log_debug("put: {}-{} get: {}", cc, c2, gv)

cc = db:puts({ 234, 3, 5 })
log_debug("puts: {}", cc)

local gv2, e = db:get(2)
log_debug("get: {} code: {}", gv2, e)

local gs = db:gets({ 1, 2, 3, 11 })
log_debug("gets: {}", gs)

for _k, _v in db:iter() do
    log_debug("iter: {}-{}", _k, _v)
end

local ee = db:del(2)
log_debug("del: {}", ee)

gv2, e = db:get(2)
log_debug("get: {} code: {}", gv2, e)

ee = db:dels({ 1, 2 })
log_debug("dels: {}", ee)

for _k, _v in db:iter() do
    log_debug("iter: {}-{}", _k, _v)
end
