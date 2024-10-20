local log_debug      = logger.debug

local event_mgr      = hive.get("event_mgr")
local monitor_mgr    = hive.get("monitor_mgr")

local MonitorServlet = singleton()

function MonitorServlet:__init()
    event_mgr:add_listener(self, "rpc_query_services")

end

-- 查询服务信息
function MonitorServlet:rpc_query_services(client, service_name)
    log_debug("[MonitorServlet][rpc_query_services] {}", service_name)
    local sids, count = monitor_mgr:query_services(service_name)
    return { sids = sids, count = count }
end

-- export
hive.monitor_servlet = MonitorServlet()

return MonitorServlet
