--graylog_test.lua

local GrayLog   = import("driver/graylog.lua")

local timer_mgr = hive.get("timer_mgr")

local glog1 = GrayLog("9.134.163.87:8081/tcp")
timer_mgr:register(2000, 1000, 2, function()
    print("GrayLog tcp test:" .. hive.now)
    glog1:write("logger tcp test" .. hive.now, 1)
end)

local glog2 = GrayLog("9.134.163.87:8080/http")
timer_mgr:register(2000, 1000, 2, function()
    print("GrayLog http test:" .. hive.now)
    glog2:write("logger http test" .. hive.now, 2)
end)

local glog3 = GrayLog("9.134.163.87:8081/udp")
timer_mgr:register(2000, 1000, 2, function()
    print("GrayLog udp test:" .. hive.now)
    glog3:write("logger udp test" .. hive.now, 2)
end)

--os.exit()
