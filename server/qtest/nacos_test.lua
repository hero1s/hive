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
    log_debug("create_namespace: {}", cres)
    local nss = nacos:query_namespaces()
    log_debug("query_namespaces: {}", nss)

    --[[
    local mres = nacos:modify_namespace("1234567", "hive", "test create_namespace2")
    log_debug("modify_namespace: {}", mres)
    local nss3 = nacos:query_namespaces()
    log_debug("query_namespaces3: {}", nss3)

    local dres = nacos:del_namespace("1234567")
    log_debug("del_namespace: {}", dres)
    local nss4 = nacos:query_namespaces()
    log_debug("query_namespaces4: {}", nss4)
    ]]

    local value = lhex_encode(lrandomkey())
    local pfres = nacos:modify_config("test2", value)
    log_debug("modify_config: test-> {}, success-> {}", value, pfres)

    local cfres = nacos:get_config("test2")
    log_debug("get_config: test-> {}", cfres)
    local dfres = nacos:del_config("test2")
    log_debug("del_config: test-> {}", dfres)

    local sres = nacos:create_service("lobby", "hive")
    log_debug("create_service: lobby-> {}", sres)
    local sres2 = nacos:create_service("lobby2", "hive")
    log_debug("create_service: lobby2-> {}", sres2)
    local mres = nacos:modify_service("lobby2", "hive")
    log_debug("modify_service: lobby-> {}", mres)
    local qres = nacos:query_service("lobby", "hive")
    log_debug("query_service: lobby-> {}", qres)
    local ok, qlres = nacos:query_services(1, 20, "hive")
    log_debug("query_services: hive->{}, {}", ok, qlres)
    local dres = nacos:del_service("lobby2", "hive")
    log_debug("del_service: hive-> {}", dres)

    local rres = nacos:regi_instance("lobby2", hive.host, 1, "hive")
    log_debug("regi_instance: lobby2-> {}", rres)
    local ilres = nacos:query_instances("lobby2", "hive")
    log_debug("query_instances: lobby2-> {}", ilres)
    local ires = nacos:query_instance("lobby2", hive.host, 1, "hive")
    log_debug("query_instance: lobby2-> {}", ires)
    local dires = nacos:del_instance("lobby2", hive.host, 1, "hive")
    log_debug("del_instance: lobby2-> {}", dires)

    nacos:listen_config("test", nil, nil, function(data_id, group, md5, cvalue)
        log_debug("listen_config: test-> {}", cvalue)
    end)
end)

timer_mgr:loop(3000, function()
    --[[
    local value = lhex_encode(lrandomkey())
    local pfres = nacos:modify_config("test", value)
    log_debug("modify_config: test-> {}, success-> {}", value, pfres)
    ]]
    local ilres = nacos:query_instances("lobby2", "hive")
    log_debug("query_instances: lobby2-> {}", ilres)
    --local bres = nacos:sent_beat("lobby2", 2, "hive")
    --log_debug("sent_beat: lobby-> {}", bres)
end)

