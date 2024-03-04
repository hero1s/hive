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
driver.open("./lmdb/xxx.lmdb", MDB_NOSUBDIR, 0644)

driver.begin_txn("test", MDB_CREATE)
local a = driver.put("abc1", { a = 123 })
local b = driver.put("abc2", "234")
local c = driver.put("abc3", "235")
log_debug("{}-{}", a, b)
driver.commit_txn()

driver.begin_txn("test")
local aa = driver.get("abc1")
local bb = driver.get("abc2")
log_debug("{}-{}", aa, bb)
local aa = driver.get("abc4")
local bb = driver.get("abc5")
log_debug("{}-{}", aa, bb)
driver.commit_txn()

driver.begin_txn("test")
driver.cursor_open()
local v, k, c = driver.cursor_get("abc1", MDB_SET)
while v do
    log_debug("{}-{}-{}", v, k, c)
    k, v, c = driver.cursor_get(0, MDB_NEXT)
end
driver.commit_txn()

local b = driver.easy_put("abc4", { a = 123 })
local c = driver.easy_put("abc5", "235")
log_debug("{}-{}", a, b)
local aa, c = driver.easy_get("abc1")
local bb, d = driver.easy_get("abc2")
log_debug("{}-{}-{}-{}", aa, bb, c, d)
local aa, c = driver.easy_get("abc4")
local bb, d = driver.easy_get("abc5")
log_debug("{}-{}-{}-{}", aa, bb, c, d)
local bb = driver.easy_del("abc5")
local bb = driver.easy_del("abc4")
local aa = driver.easy_get("abc4")
local bb = driver.easy_get("abc5")
log_debug("{}-{}", aa, bb)
