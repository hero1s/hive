--ws_server.lua
local WebSocket  = import("driver/websocket.lua")

local log_info   = logger.info
local log_debug  = logger.debug
local signalquit = signal.quit
local saddr      = string_ext.addr

local WSServer   = class()
local prop       = property(WSServer)
prop:reader("listener", nil)        --网络连接对象
prop:reader("ip", nil)              --WS server地址
prop:reader("port", 8191)           --WS server端口
prop:reader("clients", {})          --clients

function WSServer:__init(ws_addr)
    self:setup(ws_addr)
end

function WSServer:setup(ws_addr)
    self.ip, self.port = saddr(ws_addr)
    local socket       = WebSocket(self)
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

--回调
function WSServer:on_socket_recv(socket, token, message)
    log_debug("[WSServer][on_socket_recv] client(token:%s) msg:%s!", token, message)
    socket:send_frame(message)
end

return WSServer
