-- influx_test.lua
local Influx    = import("driver/influx.lua")

local log_debug = logger.debug

local timer_mgr = hive.get("timer_mgr")

local ip = "9.134.163.87"
local port = 8086
local org = "xiyoo0812"
local bucket = "testdb"
local token = "d5SUTYyl4jou8BNN4Ee2kn1U0IhWuj3P7qR7JDU_59e7UAzW0yQq_oCyLcHbFt7nX_45yYfDCsmF7beZd6LiSQ=="

local influx    = Influx(ip, port, org, bucket, token)

timer_mgr:once(2000, function()
    local _, orgs = influx:find_org()
    log_debug("find_org: %s", orgs)
    local _, bucket1 = influx:create_bucket("testdb")
    log_debug("create_bucket: %s", bucket1)
    local _, bucket2 = influx:find_bucket("testdb")
    log_debug("find_bucket: %s", bucket2)
    local res = influx:delete_bucket_by_id(bucket2.id)
    log_debug("delete_bucket_by_id: %s", res)
    local _, bucket3 = influx:create_bucket("testdb")
    log_debug("create_bucket: %s", bucket3)
    local ok1, wres = influx:write("test_tab", {type = 3}, {id = 5, name = "3333", exp = 666})
    log_debug("write: ok1: %s, res:%s", ok1, wres)
    local ok2, qres = influx:query([[from(bucket: "testdb")
    |> range(start: -12h)
    |> filter(fn: (r) => r["_measurement"] == "test_tab")
    |> filter(fn: (r) => r["_field"] == "exp" or r["_field"] == "id")
    |> filter(fn: (r) => r["type"] == "3")
    |> aggregateWindow(every: 1h, fn: mean, createEmpty: false)
    |> yield(name: "mean")]])
    log_debug("query: ok2: %s, res:%s", ok2, qres)
end)
