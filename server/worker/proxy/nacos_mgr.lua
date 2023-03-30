local log_debug  = logger.debug
local tdiff      = table_ext.diff

local PeriodTime = enum("PeriodTime")

local event_mgr  = hive.get("event_mgr")
local timer_mgr  = hive.get("timer_mgr")
local thread_mgr = hive.get("thread_mgr")

local NacosMgr   = singleton()
local prop       = property(NacosMgr)
prop:reader("nacos", nil)
prop:reader("node", nil)
prop:reader("status", false)
prop:reader("services", {})

function NacosMgr:__init()
    -- 注册事件
    event_mgr:add_listener(self, "rpc_register_nacos")

    self:setup()
end

function NacosMgr:setup()
    self.open_nacos = environ.status("HIVE_NACOS_OPEN")
    if self.open_nacos then
        import("driver/nacos.lua")
        self.nacos = hive.get("nacos")
        --监听nacos
        event_mgr:add_trigger(self, "on_nacos_ready")
    end
end

function NacosMgr:rpc_register_nacos(node)
    log_debug("[NacosMgr][rpc_register_nacos] %s", node)
    self.node = node
    if not self.nacos then
        return false
    end
    self:register()
    timer_mgr:loop(PeriodTime.SECOND_5_MS, function()
        self:on_nacos_tick()
    end)
    return true
end

function NacosMgr:on_nacos_ready()
    log_debug("[NacosMgr][on_nacos_ready] nacos ready")
    thread_mgr:fork(function()
        self.nacos:modify_switchs("healthCheckEnabled", "false")
        self.nacos:modify_switchs("autoChangeHealthCheckEnabled", "false")
        self:register()
    end)
end

function NacosMgr:register()
    if not self.nacos:get_access_token() or not self.node then
        return
    end
    if not self.status then
        local metadata = { id = self.node.id, name = self.node.name }
        self.status    = self.nacos:regi_instance(self.node.service_name, self.node.host, self.node.port, nil, metadata)
    end
end

function NacosMgr:unregister()
    if self.status and self.nacos:get_access_token() then
        self.nacos:del_instance(self.node.service_name, self.node.host, self.node.port)
    end
end

function NacosMgr:on_nacos_tick()
    if not self.nacos:get_access_token() or not self.status then
        return
    end
    self.nacos:sent_beat(self.node.service_name, self.node.host, self.node.port)
    for _, service_name in pairs(self.nacos:query_services() or {}) do
        local curr = self.nacos:query_instances(service_name)
        if curr then
            local old        = self.services[service_name]
            local sadd, sdel = tdiff(old or {}, curr)
            if next(sadd) or next(sdel) then
                log_debug("[MonitorMgr][on_nacos_tick] sadd:%s, sdel: %s", sadd, sdel)
                hive.send_master("rpc_service_changed", service_name, sadd, sdel)
                self.services[service_name] = curr
            end
        end
    end
end

hive.nacos_mgr = NacosMgr()
