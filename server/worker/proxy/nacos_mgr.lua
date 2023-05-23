local log_debug  = logger.debug
local log_warn   = logger.warn
local tmerge     = table_ext.merge
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
prop:reader("watch_services", {})

function NacosMgr:__init()
    -- 注册事件
    event_mgr:add_listener(self, "rpc_register_nacos")
    event_mgr:add_listener(self, "rpc_unregister_nacos")
    event_mgr:add_listener(self, "rpc_watch_service")

    self:setup()
end

function NacosMgr:setup()
    self.open_nacos = environ.status("HIVE_NACOS_OPEN")
    if self.open_nacos then
        import("driver/nacos.lua")
        self.nacos = hive.get("nacos")
        --监听nacos
        event_mgr:add_trigger(self, "on_nacos_ready")
        timer_mgr:loop(PeriodTime.SECOND_5_MS, function()
            self:on_nacos_tick()
        end)
    end
end

function NacosMgr:rpc_register_nacos(node)
    log_debug("[NacosMgr][rpc_register_nacos] %s", node)
    self.node = node
    if not self.nacos then
        log_warn("[NacosMgr][rpc_register_nacos] nacos is nil")
        return false
    end
    self:register()
    return true
end

function NacosMgr:rpc_unregister_nacos()
    self:unregister()
    return true
end

function NacosMgr:rpc_watch_service(watch_services, pre_services)
    log_debug("[NacosMgr][rpc_watch_service] %s,%s", watch_services, pre_services)
    self.watch_services = {}
    tmerge(pre_services, watch_services)
    for _, service_name in ipairs(watch_services) do
        self.watch_services[service_name] = 1
    end
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
    self:unregister()
    if not self.status then
        local metadata = { id = self.node.id, name = self.node.name, is_ready = self.node.is_ready and 1 or 0 }
        self.status    = self.nacos:regi_instance(self.node.service_name, self.node.host, self.node.port, nil, metadata)
        log_debug("[NacosMgr][register] register:%s", self.status)
    end
end

function NacosMgr:unregister()
    if self.status and self.nacos:get_access_token() then
        local ret = self.nacos:del_instance(self.node.service_name, self.node.host, self.node.port)
        if ret then
            self.status = false
        end
    end
end

function NacosMgr:need_watch(service_name)
    if self.watch_services[service_name] or self.watch_services["*"] then
        return true
    end
    return false
end

function NacosMgr:on_nacos_tick()
    thread_mgr:entry("on_nacos_tick", function()
        if not self.nacos:get_access_token() or not self.status then
            return
        end
        self.nacos:sent_beat(self.node.service_name, self.node.host, self.node.port)
        for _, service_name in pairs(self.nacos:query_services() or {}) do
            if self:need_watch(service_name) then
                local curr = self.nacos:query_instances(service_name)
                if curr then
                    if not self.services[service_name] then
                        self.services[service_name] = {}
                    end
                    local old        = self.services[service_name]
                    local sadd, sdel = {}, {}
                    for id, node in pairs(old) do
                        if not curr[id] or curr[id].is_ready ~= 1 then
                            sdel[id] = node
                        end
                    end
                    for id, node in pairs(curr) do
                        if node.is_ready == 1 and not old[id] then
                            sadd[id] = node
                        end
                    end
                    for id, node in pairs(sadd) do
                        old[id] = node
                    end
                    for id, node in pairs(sdel) do
                        old[id] = nil
                    end
                    if next(sadd) or next(sdel) then
                        log_debug("[MonitorMgr][on_nacos_tick] sadd:%s, sdel: %s", sadd, sdel)
                        hive.send_master("rpc_service_changed", service_name, sadd, sdel)
                    end
                end
            end
        end
    end)
end

hive.nacos_mgr = NacosMgr()
