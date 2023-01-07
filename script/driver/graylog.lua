--graylog.lua
import("network/http_client.lua")
local luabus      = require("luabus")
local ljson       = require("lcjson")

local log_err     = logger.err
local log_info    = logger.info
local json_encode = ljson.encode
local sformat     = string.format
local dgetinfo    = debug.getinfo
local tcopy       = table_ext.copy
local protoaddr   = string_ext.protoaddr

local update_mgr  = hive.get("update_mgr")
local http_client = hive.get("http_client")
local thread_mgr  = hive.get("thread_mgr")

local Socket      = import("driver/socket.lua")

local GrayLog     = singleton()
local prop        = property(GrayLog)
prop:reader("ip", nil)          --地址
prop:reader("tcp", nil)         --网络连接对象
prop:reader("udp", nil)         --网络连接对象
prop:reader("port", 12021)      --端口
prop:reader("addr", nil)        --http addr
prop:reader("proto", nil)       --proto

function GrayLog:__init()
    local addr = environ.get("HIVE_GRAYLOG_ADDR")
    if not addr then
        return
    end
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
    self.udp = luabus.udp()
    log_info("[GrayLog][setup] setup udp (%s:%s) success!", self.ip, self.port)
end

function GrayLog:close()
    if self.tcp then
        self.tcp:close()
    end
end

function GrayLog:on_second()
    local _lock<close> = thread_mgr:lock("graylog-second", true)
    if not _lock then
        return
    end
    if not self.tcp:is_alive() then
        if not self.tcp:connect(self.ip, self.port) then
            log_err("[GrayLog][on_second] connect (%s:%s) failed!", self.ip, self.port, self.name)
            return
        end
        log_info("[GrayLog][on_second] connect (%s:%s) success!", self.ip, self.port, self.name)
    end
end

function GrayLog:build(message, level, optional)
    local debug_info = dgetinfo(6, "S")
    local gelf       = {
        level         = level,
        version       = "1.1",
        host          = hive.host,
        timestamp     = hive.now,
        short_message = message,
        file          = debug_info.short_src,
        line          = debug_info.linedefined,
        _service      = hive.service,
        _index        = hive.index,
        _name         = hive.name,
        _id           = hive.id,
    }
    if optional then
        tcopy(optional, gelf)
    end
    return gelf
end

function GrayLog:write(message, level, optional)
    if not self.proto then
        return
    end
    local gelf = self:build(message, level, optional)
    if self.proto == "http" and self.addr then
        http_client:call_post(self.addr, gelf)
        return
    end
    if self.proto == "tcp" then
        if self.tcp and self.tcp:is_alive() then
            self.tcp:send(sformat("%s\0", json_encode(gelf)))
        end
        return
    end
    if self.udp then
        local udpmsg = json_encode(gelf)
        self.udp.send(udpmsg, self.ip, self.port)
    end
end

hive.graylog = GrayLog()

return GrayLog
