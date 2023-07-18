--http_server.lua
local lhttp             = require("lhttp")
local Socket            = import("driver/socket.lua")

local type              = type
local tostring          = tostring
local log_warn          = logger.warn
local log_info          = logger.info
local log_debug         = logger.debug
local log_err           = logger.err
local json_encode       = hive.json_encode
local tunpack           = table.unpack
local signal_quit       = signal.quit
local saddr             = string_ext.addr

local HTTP_CALL_TIMEOUT = hive.enum("NetwkTime", "HTTP_CALL_TIMEOUT")
local thread_mgr        = hive.get("thread_mgr")

local HttpServer        = class()
local prop              = property(HttpServer)
prop:reader("listener", nil)        --网络连接对象
prop:reader("ip", nil)              --http server地址
prop:reader("port", 8080)           --http server端口
prop:reader("clients", {})          --clients
prop:reader("requests", {})         --requests
prop:reader("get_handlers", {})     --get_handlers
prop:reader("put_handlers", {})     --put_handlers
prop:reader("del_handlers", {})     --del_handlers
prop:reader("post_handlers", {})    --post_handlers
prop:accessor("limit_ips", nil)

function HttpServer:__init(http_addr, induce)
    self:setup(http_addr, induce)
end

function HttpServer:setup(http_addr, induce)
    self.ip, self.port = saddr(http_addr)
    self.port          = induce and (self.port + hive.index - 1) or self.port
    local socket       = Socket(self)
    socket:set_timeout(HTTP_CALL_TIMEOUT)
    if not socket:listen(self.ip, self.port) then
        log_err("[HttpServer][setup] now listen %s failed", http_addr)
        signal_quit(1)
        return
    end
    log_info("[HttpServer][setup] listen(%s:%s) success!", self.ip, self.port)
    self.listener = socket
end

function HttpServer:close(token, socket)
    self.clients[token]  = nil
    self.requests[token] = nil
    socket:close()
end

function HttpServer:on_socket_error(socket, token, err)
    if socket == self.listener then
        log_info("[HttpServer][on_socket_error] listener(%s:%s) close!", self.ip, self.port)
        self.listener = nil
        return
    end
    self.clients[token]  = nil
    self.requests[token] = nil
end

function HttpServer:on_socket_accept(socket, token)
    local ip = socket.ip
    if self.limit_ips and self.limit_ips[ip] == nil then
        log_warn("[HttpServer][on_socket_accept] limit white ip visit:%s", ip)
        socket:close()
        return
    end
    self.clients[token] = socket
end

function HttpServer:on_socket_recv(socket, token)
    local client = self.clients[token]
    if not client then
        return
    end
    local request = self.requests[token]
    if not request then
        request              = lhttp.create_request()
        self.requests[token] = request
    end
    local buf = socket:get_recvbuf()
    if not request.parse(buf) then
        return
    end
    socket:pop(#buf)
    thread_mgr:fork(function()
        local method = request.method
        if method == "GET" then
            return self:on_http_request(self.get_handlers, socket, request.url, request.get_params(), request)
        end
        if method == "POST" then
            return self:on_http_request(self.post_handlers, socket, request.url, request.body, request)
        end
        if method == "PUT" then
            return self:on_http_request(self.put_handlers, socket, request.url, request.body, request)
        end
        if method == "DELETE" then
            return self:on_http_request(self.del_handlers, socket, request.url, request.get_params(), request)
        end
    end)
end

--注册get回调
function HttpServer:register_get(url, handler, target)
    log_debug("[HttpServer][register_get] url: %s", url)
    self.get_handlers[url] = { handler, target }
end

--注册post回调
function HttpServer:register_post(url, handler, target)
    log_debug("[HttpServer][register_post] url: %s", url)
    self.post_handlers[url] = { handler, target }
end

--注册put回调
function HttpServer:register_put(url, handler, target)
    log_debug("[HttpServer][register_put] url: %s", url)
    self.put_handlers[url] = { handler, target }
end

--注册del回调
function HttpServer:register_del(url, handler, target)
    log_debug("[HttpServer][register_del] url: %s", url)
    self.del_handlers[url] = { handler, target }
end

--http post 回调
function HttpServer:on_http_request(handlers, socket, url, ...)
    local handler_info = handlers[url] or handlers["*"]
    if handler_info then
        local handler, target = tunpack(handler_info)
        if not target then
            if type(handler) == "function" then
                local ok, response, headers = pcall(handler, url, ...)
                if not ok then
                    response = { code = 1, msg = response }
                end
                self:response(socket, 200, response, headers)
                return
            end
        else
            if type(handler) == "string" then
                handler = target[handler]
            end
            if type(handler) == "function" then
                local ok, response, headers = pcall(handler, target, url, ...)
                if not ok then
                    log_err("[HttpServer][on_http_request] ok:%s, response:%s", ok, response)
                    response = { code = 1, msg = response }
                end
                self:response(socket, 200, response, headers)
                return
            end
        end
    end
    log_warn("[HttpServer][on_http_request] request %s hasn't process!", url)
    self:response(socket, 404, "this http request hasn't process!")
end

function HttpServer:response(socket, status, response, headers)
    local token = socket:get_token()
    if not token or not response then
        return
    end
    local new_resp = lhttp.create_response()
    for key, value in pairs(headers or {}) do
        new_resp.set_header(key, value)
    end
    new_resp.set_header("connection", "close")
    if type(response) == "table" then
        new_resp.set_header("Content-Type", "application/json")
        new_resp.content = json_encode(response)
    elseif type(response) == "string" then
        new_resp.content = response
        local html       = response:find("<html")
        new_resp.set_header("Content-Type", html and "text/html" or "text/plain")
    else
        new_resp.set_header("Content-Type", "text/plain")
        new_resp.content = tostring(response)
    end
    new_resp.status = status
    socket:send(new_resp.serialize())
    self:close(token, socket)
end

--取消url
function HttpServer:unregister(url)
    self.get_handlers[url]  = nil
    self.put_handlers[url]  = nil
    self.del_handlers[url]  = nil
    self.post_handlers[url] = nil
end

return HttpServer
