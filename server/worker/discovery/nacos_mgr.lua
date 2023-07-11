local log_debug  = logger.debug
local log_warn   = logger.warn
local PeriodTime = enum("PeriodTime")
local makechan   = hive.make_channel
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
    return self:register()
end

function NacosMgr:rpc_unregister_nacos()
    self:unregister()
    return true
end

function NacosMgr:rpc_watch_service(watch_services, pre_services)
    log_debug("[NacosMgr][rpc_watch_service] %s,%s", watch_services, pre_services)
    self.watch_services = {}
    for _, service_name in ipairs(watch_services) do
        self.watch_services[service_name] = 1
    end
    for _, service_name in ipairs(pre_services) do
        self.watch_services[service_name] = 1
    end
    log_debug("[NacosMgr][rpc_watch_service] watch:%s", self.watch_services)
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
    if not self.nacos:get_access_token() then
        log_debug("[NacosMgr][register] nacos not ready")
        return false
    end
    self:unregister()
    if not self:can_register() then
        return false
    end
    if not self.status then
        local metadata = { id = self.node.id, name = self.node.name, is_ready = self.node.is_ready and 1 or 0 }
        self.status    = self.nacos:regi_instance(self.node.service_name, self.node.host, self.node.port, nil, metadata)
        log_debug("[NacosMgr][register] register:%s", self.status)
    end
    return self.status
end

function NacosMgr:unregister()
    if self.status and self.nacos:get_access_token() then
        local ret = self.nacos:del_instance(self.node.service_name, self.node.host, self.node.port)
        if ret then
            log_debug("[NacosMgr][unregister] remove:%s", self.node)
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

function NacosMgr:can_register()
    if not self.node or not self.node.id or not self.node.host or not self.node.port then
        return false
    end
    if self.node.is_ready then
        return true
    end
    return false
end

function NacosMgr:can_add_service(service_name)
    if not self.node then
        return false
    end
    if self.node.is_ready then
        return true
    end
    if not self.status then
        return service_name == "router"
    end
    return false
end

function NacosMgr:check_service(service_name)
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
            if self:can_add_service(service_name) then
                if node.is_ready == 1 and not old[id] then
                    sadd[id] = node
                end
            end
        end
        for id, node in pairs(sadd) do
            old[id] = node
        end
        for id, node in pairs(sdel) do
            old[id] = nil
        end
        if next(sadd) or next(sdel) then
            log_debug("[NacosMgr][on_nacos_tick] sadd:%s, sdel: %s", sadd, sdel)
            hive.send_master("rpc_service_changed", service_name, sadd, sdel)
        end
    end
end

function NacosMgr:on_nacos_tick()
    thread_mgr:entry("on_nacos_tick", function()
        if not self.nacos:get_access_token() then
            return
        end
        if self.status then
            local ok = self.nacos:sent_beat(self.node.service_name, self.node.host, self.node.port)
            if not ok then
                self:register()
            end
        else
            self:register()
        end
        local ok, lists = self.nacos:query_services()
        if not ok then
            return
        end
        local channel = makechan("nacos-check-service", 1000)
        for _, service_name in pairs(lists or {}) do
            if self:need_watch(service_name) then
                channel:push(function()
                    self:check_service(service_name)
                    return true, 0
                end)
            end
        end
        channel:execute(true)
    end)
end

hive.nacos_mgr = NacosMgr()
