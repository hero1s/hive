--ws_server.lua
local ljson         = require("lcjson")
local WebSocket     = import("driver/websocket.lua")

local type          = type
local log_err       = logger.err
local log_info      = logger.info
local log_debug     = logger.debug
local json_encode   = ljson.encode
local tunpack       = table.unpack
local signalquit    = signal.quit
local saddr         = string_ext.addr

local WSServer = class()
local prop = property(WSServer)
prop:reader("listener", nil)        --网络连接对象
prop:reader("ip", nil)              --WS server地址
prop:reader("port", 8191)           --WS server端口
prop:reader("mode", "text")         --发送类型(text/binary)
prop:reader("clients", {})          --clients
prop:reader("handlers", {})         --get_handlers

function WSServer:__init(ws_addr)
    self:setup(ws_addr)
end

function WSServer:setup(ws_addr)
    self.ip, self.port = saddr(ws_addr)
    local socket = WebSocket(self)
    if not socket:listen(self.ip, self.port) then
        log_info("[WSServer][setup] now listen %s failed", ws_addr)
        signalquit(1)
        return
    end
    log_info("[WSServer][setup] listen(%s:%s) success!", self.ip, self.port)
    self.listener = socket
end

function WSServer:on_socket_error(socket, token, err)
    if socket == self.listener then
        log_info("[WSServer][on_socket_error] listener(%s:%s) close!", self.ip, self.port)
        self.listener = nil
        return
    end
    log_debug("[WSServer][on_socket_error] client(token:%s) close!", token)
    self.clients[token] = nil
end

function WSServer:on_socket_accept(socket, token)
    log_debug("[WSServer][on_socket_accept] client(token:%s) connected!", token)
    self.clients[token] = socket
end

--注册回调
function WSServer:register_handler(url, handler, target)
    log_debug("[WSServer][register_handler] url: %s", url)
    self.handlers[url] = { handler, target }
end

--回调
function WSServer:on_socket_recv(socket, token, message)
    local url = socket:get_url()
    local handler_info = self.handlers[url] or self.handlers["*"]
    if handler_info then
        local handler, target = tunpack(handler_info)
        if not target then
            if type(handler) == "function" then
                local ok, response = pcall(handler, url, message)
                if not ok then
                    response = { code = 1, msg = response }
                end
                self:response(socket, response)
                return
            end
        else
            if type(handler) == "string" then
                handler = target[handler]
            end
            if type(handler) == "function" then
                local ok, response = pcall(handler, target, url, message)
                if not ok then
                    response = { code = 1, msg = response }
                end
                self:response(socket, response)
                return
            end
        end
    end
    log_err("[WSServer][on_socket_recv] request %s hasn't process!", url)
end

function WSServer:response(socket, ws_res)
    if type(ws_res) == "table" then
        ws_res = json_encode(ws_res)
    end
    if type(ws_res) ~= "string" then
        ws_res = tostring(ws_res)
    end
    if self.mode == "text" then
        socket:send_text(ws_res)
        return
    end
    socket:send_binary(ws_res)
end

return WSServer
