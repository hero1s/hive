-- zipkin_test.lua
import("driver/zipkin.lua")

local zipkin        = hive.get("zipkin")
local timer_mgr     = hive.get("timer_mgr")
local event_mgr     = hive.get("event_mgr")
local router_mgr    = hive.get("router_mgr")

local function zipkin_func4(span)
    local key4 = 44
    local nspan = zipkin:sub_span("zipkin_func4", span.id)
    zipkin:set_tag(nspan, "key4", key4)
    zipkin:set_annotation(nspan, "call zipkin_func4!")
    zipkin:finish_span(nspan)
end

local function zipkin_func3(span)
    local key3 = 33
    local nspan = zipkin:sub_span("zipkin_func3", span.id)
    zipkin:set_tag(nspan, "key3", key3)
    zipkin:set_annotation(nspan, "call zipkin_func3!")
    zipkin_func4(nspan)
end

local function zipkin_func2(span)
    local key2 = 22
    local nspan = zipkin:sub_span("zipkin_func2", span.id)
    zipkin:set_tag(nspan, "key2", key2)
    zipkin:set_annotation(nspan, "call zipkin_func2!")
    local rspan = zipkin:inject_span(nspan)
    local target = service.make_id("test", 2)
    local ok, res =  router_mgr:call_target(target, "rpc_zipkin_test", rspan)
    if ok and res then
        local fspan = zipkin:sub_span("zipkin_finish", nspan.id)
        zipkin:set_annotation(fspan, "call zipkin finish!")
        zipkin:set_tag(fspan, "key5", "5555")
        zipkin:finish_span(fspan)
    end
end

local function zipkin_func1()
    local key1 = 11
    local span = zipkin:new_span("zipkin_func1")
    zipkin:set_tag(span, "key1", key1)
    zipkin:set_annotation(span, "call zipkin_func1!")
    zipkin_func2(span)
end

timer_mgr:once(2000, function()
    if hive.index == 1 then
        zipkin_func1()
    else
        hive.testobj = {
            ["rpc_zipkin_test"] = function(self, span)
                local nspan = zipkin:recovery_span(span)
                zipkin_func3(nspan)
                return true
            end
        }
        event_mgr:add_listener(hive.testobj, "rpc_zipkin_test")
    end
end)

