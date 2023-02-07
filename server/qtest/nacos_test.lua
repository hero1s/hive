-- nacos_test.lua
import("driver/nacos.lua")
local lcrypt      = require("lcrypt")

local log_debug   = logger.debug
local lhex_encode = lcrypt.hex_encode
local lrandomkey  = lcrypt.randomkey

local nacos       = hive.get("nacos")
local timer_mgr   = hive.get("timer_mgr")
local thread_mgr  = hive.get("thread_mgr")

thread_mgr:fork(function()
    local cres = nacos:create_namespace("1234567", "hive", "test create_namespace")
    log_debug("create_namespace: %s", cres)
    local nss = nacos:query_namespaces()
    log_debug("query_namespaces: %s", nss)

    --[[
    local mres = nacos:modify_namespace("1234567", "hive", "test create_namespace2")
    log_debug("modify_namespace: %s", mres)
    local nss3 = nacos:query_namespaces()
    log_debug("query_namespaces3: %s", nss3)

    local dres = nacos:del_namespace("1234567")
    log_debug("del_namespace: %s", dres)
    local nss4 = nacos:query_namespaces()
    log_debug("query_namespaces4: %s", nss4)
    ]]

    local value = lhex_encode(lrandomkey())
    local pfres = nacos:modify_config("test2", value)
    log_debug("modify_config: test-> %s, success-> %s", value, pfres)

    local cfres = nacos:get_config("test2")
    log_debug("get_config: test-> %s", cfres)
    local dfres = nacos:del_config("test2")
    log_debug("del_config: test-> %s", dfres)

    local sres = nacos:create_service("lobby", "hive")
    log_debug("create_service: lobby-> %s", sres)
    local sres2 = nacos:create_service("lobby2", "hive")
    log_debug("create_service: lobby2-> %s", sres2)
    local mres = nacos:modify_service("lobby2", "hive")
    log_debug("modify_service: lobby-> %s", mres)
    local qres = nacos:query_service("lobby", "hive")
    log_debug("query_service: lobby-> %s", qres)
    local qlres = nacos:query_services(1, 20, "hive")
    log_debug("query_services: hive-> %s", qlres)
    local dres = nacos:del_service("lobby2", "hive")
    log_debug("del_service: hive-> %s", dres)

    local rres = nacos:regi_instance("lobby2", hive.host, 1, "hive")
    log_debug("regi_instance: lobby2-> %s", rres)
    local ilres = nacos:query_instances("lobby2", "hive")
    log_debug("query_instances: lobby2-> %s", ilres)
    local ires = nacos:query_instance("lobby2", hive.host, 1, "hive")
    log_debug("query_instance: lobby2-> %s", ires)
    local dires = nacos:del_instance("lobby2", hive.host, 1, "hive")
    log_debug("del_instance: lobby2-> %s", dires)

    nacos:listen_config("test", nil, nil, function(data_id, group, md5, cvalue)
        log_debug("listen_config: test-> %s", cvalue)
    end)
end)

timer_mgr:loop(3000, function()
    --[[
    local value = lhex_encode(lrandomkey())
    local pfres = nacos:modify_config("test", value)
    log_debug("modify_config: test-> %s, success-> %s", value, pfres)
    ]]
    local ilres = nacos:query_instances("lobby2", "hive")
    log_debug("query_instances: lobby2-> %s", ilres)
    --local bres = nacos:sent_beat("lobby2", 2, "hive")
    --log_debug("sent_beat: lobby-> %s", bres)
end)

