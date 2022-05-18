-- clickhouse_test.lua
local log_debug = logger.debug

local timer_mgr = hive.get("timer_mgr")

local ClickHouseMgr = import("store/clickhouse_mgr.lua")
local ck_mgr = ClickHouseMgr()

timer_mgr:once(2000, function()
    local code, res_oe = ck_mgr:execute("default", "drop table if exists test_ck")
    log_debug("db drop table code: %s, err = %s", code, res_oe)
    code, res_oe = ck_mgr:execute("default", "create table if not exists test_ck (id int, pid int, value int, primary key (id)) ENGINE = MergeTree")
    log_debug("db create table code: %s, err = %s", code, res_oe)
    code, res_oe = ck_mgr:execute("default", "select count(*) as count from test_ck where pid=123456")
    log_debug("db select code: %s, count = %s", code, res_oe)
    code, res_oe = ck_mgr:execute("default", "insert into test_ck (id, pid, value) values (1, 123456, 40)")
    log_debug("db insert code: %s, count = %s", code, res_oe)
    code, res_oe = ck_mgr:execute("default", "select * from test_ck where pid = 123456")
    log_debug("db select code: %s, res_oe = %s", code, res_oe)

end)
