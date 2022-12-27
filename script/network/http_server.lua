--http_server.lua
local lhttp       = require("lhttp")
local Socket      = import("driver/socket.lua")

local type        = type
local tostring    = tostring
local log_err     = logger.err
local log_warn    = logger.warn
local log_info    = logger.info
local log_debug   = logger.debug
local json_encode = hive.json_encode
local tunpack     = table.unpack
local signal_quit = signal.quit
local saddr       = string_ext.addr

local thread_mgr  = hive.get("thread_mgr")

local HttpServer  = class()
local prop        = property(HttpServer)
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
    if not socket:listen(self.ip, self.port) then
        log_info("[HttpServer][setup] now listen %s failed", http_addr)
        signal_quit(1)
        return
    end
    log_info("[HttpServer][setup] listen(%s:%s) success!", self.ip, self.port)
    self.listener = socket
end

function HttpServer:on_socket_error(socket, token, err)
    if socket == self.listener then
        log_info("[HttpServer][on_socket_error] listener(%s:%s) close!", self.ip, self.port)
        self.listener = nil
        return
    end
    log_debug("[HttpServer][on_socket_error] client(token:%s) close!", token)
    self.clients[token]  = nil
    self.requests[token] = nil
end

function HttpServer:on_socket_accept(socket, token)
    local ip = socket.ip
    log_debug("[HttpServer][on_socket_accept] client(token:%s,ip:%s) connected!", token, ip)
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
        request = lhttp.create_request()
        log_debug("[HttpServer][on_socket_recv] create_request(token:%s)!", token)
        self.requests[token] = request
    end
    local buf = socket:get_recvbuf()
    if #buf == 0 or not request.parse(buf) then
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

--生成response
function HttpServer:build_response(status, content, headers)
    local response = lhttp.create_response()
    response.set_header("Access-Control-Allow-Origin", "*")
    response.set_header("connection", "close")
    if type(content) == "table" then
        response.set_header("Content-Type", "application/json")
        response.content = json_encode(content)
    else
        response.content = (type(content) == "string") and content or tostring(content)
    end
    response.status = status
    for name, value in pairs(headers or {}) do
        response.set_header(name, value)
    end
    return response
end

--http post 回调
function HttpServer:on_http_request(handlers, socket, url, ...)
    log_info("[HttpServer][on_http_request] request %s process!", url)
    local handler_info = handlers[url] or handlers["*"]
    if handler_info then
        local handler, target = tunpack(handler_info)
        if not target then
            if type(handler) == "function" then
                local ok, response = pcall(handler, url, ...)
                if not ok then
                    response = { code = 1, msg = response }
                end
                self:response(socket, 200, response)
                return
            end
        else
            if type(handler) == "string" then
                handler = target[handler]
            end
            if type(handler) == "function" then
                local ok, response = pcall(handler, target, url, ...)
                if not ok then
                    response = { code = 1, msg = response }
                end
                self:response(socket, 200, response)
                return
            end
        end
    end
    log_warn("[HttpServer][on_http_request] request %s hasn't process!", url)
    self:response(socket, 404, "this http request hasn't process!")
end

function HttpServer:response(socket, status, response)
    local token = socket:get_token()
    if not token then
        return
    end
    self.requests[token] = nil
    if type(response) == "table" and response.__pointer__ then
        if response.serialize then
            socket:send(response.serialize())
            socket:close()
            return
        else
            log_err("[HttpServer][response] the unknow table:%s", response)
        end
    end
    local new_resp = lhttp.create_response()
    new_resp.set_header("Access-Control-Allow-Origin", "*")
    new_resp.set_header("connection", "close")
    if type(response) == "table" then
        new_resp.set_header("Content-Type", "application/json")
        new_resp.content = json_encode(response)
    else
        new_resp.set_header("Content-Type", "text/plain")
        new_resp.content = (type(response) == "string") and response or tostring(response)
    end
    new_resp.status = status
    socket:send(new_resp.serialize())
    socket:close()
end

return HttpServer
