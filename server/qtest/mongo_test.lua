-- mongo_test.lua
local log_debug = logger.debug

local timer_mgr = hive.get("timer_mgr")

local MongoMgr  = import("store/mongo_mgr.lua")
local mongo_mgr = MongoMgr()

timer_mgr:once(2000, function()
    local code, count = mongo_mgr:count("default", nil, "test_mongo_1", { pid = 123456, uid = 1, ttl = bson.date(os.time() + 1) })
    log_debug("db count code: {}, count = {}", code, count)
    local icode, ierr = mongo_mgr:insert("default", nil, "test_mongo_1", { pid = 123456, uid = 2, data = { a = 1, b = 2 }, ttl = bson.date(os.time() + 2) })
    log_debug("db insert code: {}, err = {}", icode, ierr)
    icode, ierr = mongo_mgr:insert("default", nil, "test_mongo_1", { pid = 123457, uid = 0, data = { a = 1, b = 2 }, ttl = bson.date(os.time() + 3) })
    log_debug("db insert code: {}, err = {}", icode, ierr)
    local fcode, res = mongo_mgr:find("default", nil, "test_mongo_1", {}, { _id = 0 }, { ttl = 1 })
    log_debug("db find code: {}, res = {}", fcode, res)
    local f1code, f1res = mongo_mgr:find_one("default", nil, "test_mongo_1", { pid = 123456 }, { _id = 0 })
    log_debug("db find code: {}, res = {}", f1code, f1res)
    local ucode, uerr = mongo_mgr:update("default", nil, "test_mongo_1", { pid = 123458, data = { a = 1, b = 4 } }, { pid = 123458 })
    log_debug("db update code: {}, err = {}", ucode, uerr)
    local ucode2, uerr2 = mongo_mgr:update("default", nil, "test_mongo_1", { ["$setOnInsert"] = { pid = 123458, data = { a = 1, b = 4 } } }, { pid = 123458 }, true)
    log_debug("db update code2: {}, err2 = {}", ucode2, uerr2)
    code, count = mongo_mgr:count("default", nil, "test_mongo_1", { pid = 123456 })
    log_debug("db count code: {}, count = {}", code, count)
    icode, ierr = mongo_mgr:create_indexes("default", nil, "test_mongo_2", { { key = { uid = 1 }, name = "test_uid", unique = true } })
    log_debug("db create_indexes code: {}, err = {}", icode, ierr)
    icode, ierr = mongo_mgr:create_indexes("default", nil, "test_mongo_2", { { key = { "uid", 1, "pid", -1 }, name = "test_uid2", unique = true } })
    log_debug("db create_indexes2 code: {}, err = {}", icode, ierr)
    icode, ierr = mongo_mgr:execute("default", nil, "listIndexes", "test_mongo_2")
    log_debug("db listIndexes code: {}, err = {}", icode, ierr)
    icode, ierr = mongo_mgr:drop_indexes("default", nil, "test_mongo_2", "test_uid")
    log_debug("db drop_indexes code: {}, err = {}", icode, ierr)
    fcode, res = mongo_mgr:find("default", nil, "test_mongo_1", {}, { _id = 0 }, { "ttl", 1, "uid", 1, "pid", 1, })
    for _, v in pairs(res) do
        log_debug("db find sort code: {}, v = {}", fcode, v)
    end
    icode, ierr = mongo_mgr:aggregate("default", nil, "test_mongo_1", {
        { ["$match"] = { pid = 123456 } },
        { ["$group"] = { _id = "date", count = { ["$sum"] = 1 } } }
    }, { "cursor", { batchSize = count } })
    log_debug("aggregate:{},{}", icode, ierr)
end)
