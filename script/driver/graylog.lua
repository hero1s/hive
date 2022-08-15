--graylog.lua
import("network/http_client.lua")
local lkcp        = require("lkcp")

local log_err     = logger.err
local log_info    = logger.info
local json_encode = hive.json_encode
local sformat     = string.format
local dgetinfo    = debug.getinfo
local tcopy       = table_ext.copy
local sid2sid     = service.id2sid
local sid2nick    = service.id2nick
local sid2name    = service.id2name
local sid2index   = service.id2index
local protoaddr   = string_ext.protoaddr

local Socket      = import("driver/socket.lua")
local thread_mgr  = hive.get("thread_mgr")
local update_mgr  = hive.get("update_mgr")
local http_client = hive.get("http_client")

local GrayLog     = class()
local prop        = property(GrayLog)
prop:reader("ip", nil)          --地址
prop:reader("tcp", nil)         --网络连接对象
prop:reader("udp", nil)         --网络连接对象
prop:reader("port", 12021)      --端口
prop:reader("addr", nil)        --http addr
prop:reader("proto", "http")    --proto
prop:reader("host", nil)        --host

function GrayLog:__init(addr)
    self.host             = environ.get("HIVE_HOST_IP")
    local ip, port, proto = protoaddr(addr)
    self.proto            = proto
    if proto == "http" then
        self.addr = sformat("http://%s:%s/gelf", ip, port)
        log_info("[GrayLog][setup] setup http (%s) success!", self.addr)
        return
    end
    self.ip   = ip
    self.port = port
    if proto == "tcp" then
        self.tcp = Socket(self)
        update_mgr:attach_second(self)
        log_info("[GrayLog][setup] setup tcp (%s:%s) success!", self.ip, self.port)
        return
    end
    self.udp = lkcp.udp()
    log_info("[GrayLog][setup] setup udp (%s:%s) success!", self.ip, self.port)
end

function GrayLog:http(ip, port)
end

function GrayLog:close()
    if self.tcp then
        self.tcp:close()
    end
end

function GrayLog:on_second()
    if not self.tcp:is_alive() then
        if not self.tcp:connect(self.ip, self.port) then
            log_err("[GrayLog][on_second] connect (%s:%s) failed!", self.ip, self.port, self.name)
            return
        end
        log_info("[GrayLog][on_second] connect (%s:%s) success!", self.ip, self.port, self.name)
    end
end

function GrayLog:build(message, level, optional)
    local hive_id    = hive.id
    local debug_info = dgetinfo(6, "S")
    local gelf       = {
        level         = level,
        version       = "1.1",
        host          = self.host,
        _node_id      = hive_id,
        timestamp     = hive.now,
        short_message = message,
        file          = debug_info.short_src,
        line          = debug_info.linedefined,
        _name         = sid2name(hive_id),
        _nick         = sid2nick(hive_id),
        _index        = sid2index(hive_id),
        _service      = sid2sid(hive_id)
    }
    if optional then
        tcopy(optional, gelf)
    end
    return gelf
end

function GrayLog:write(message, level, optional)
    local gelf = self:build(message, level, optional)
    if self.proto == "http" then
        thread_mgr:fork(function()
            local ok, status, res = http_client:call_post(self.addr, gelf)
            if not ok then
                print("[GrayLog][write] post failed!:", status, res)
            end
        end)
        return
    end
    if self.proto == "tcp" then
        if self.tcp and self.tcp:is_alive() then
            self.tcp:send(sformat("%s\0", json_encode(gelf)))
        end
        return
    end
    local udpmsg = json_encode(gelf)
    self.udp:send(udpmsg, #udpmsg, self.ip, self.port)
end

return GrayLog
