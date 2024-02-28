local lmdb       = require("lmdb")
local log_debug  = logger.debug

local MDB_CREATE = lmdb.MDBI_FLAG.MDB_CREATE
local MDB_FIRST  = lmdb.MDB_CUROP.MDB_FIRST
local MDB_NEXT   = lmdb.MDB_CUROP.MDB_NEXT

local env        = lmdb.create_env()
env.set_max_dbs(10)
local code = env.open("./lmdb/", 0, 0644)
log_debug("{}", code)

env.begin("test", MDB_CREATE)
local a = env.put("abc1", "123")
local b = env.put("abc2", "234")
log_debug("{}-{}", a, b)
env.commit()

env.begin("test")
local aa = env.get("abc1")
local bb = env.get("abc2")
log_debug("{}-{}", aa, bb)
env.del("abc1")
env.del("abc2")
local ac = env.get("abc1")
local bc = env.get("abc2")
log_debug("{}-{}", ac, bc)
env.commit()

env.begin("test")
env.cursor_open()
local a = env.cursor_get("abc1", MDB_FIRST)
while a do
    log_debug("{}", a)
    a = env.cursor_get("abc1", MDB_NEXT)
end
env.commit()
