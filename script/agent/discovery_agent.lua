local event_mgr      = hive.get("event_mgr")

local thread         = import("feature/worker_agent.lua")
local DiscoveryAgent = singleton(thread)

function DiscoveryAgent:__init()
    self.service = "discovery"
    self:startup("worker.discovery")

    event_mgr:add_trigger(self, "evt_change_service_status")
    event_mgr:add_trigger(self, "evt_service_shutdown")
end

function DiscoveryAgent:evt_change_service_status(service_status)
    local monitor = hive.load("monitor")
    if monitor then
        self:send("rpc_watch_service", monitor:watch_services(), hive.pre_services)
        self:send("rpc_register_nacos", hive.node_info)
    end
end

function DiscoveryAgent:evt_service_shutdown()
    self:send("rpc_unregister_nacos")
end

hive.discovery_agent = DiscoveryAgent()

return DiscoveryAgent
