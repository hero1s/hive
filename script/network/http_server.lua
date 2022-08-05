--http_server.lua
local lhttp               = require("lhttp")
local Socket              = import("driver/socket.lua")

local HTTP_SESSION_FINISH = 1
local HTTP_REQUEST_ERROR  = 2

local type                = type
local log_err             = logger.err
local log_warn            = logger.warn
local log_info            = logger.info
local log_debug           = logger.debug
local json_encode         = hive.json_encode
local tunpack             = table.unpack
local signalquit          = signal.quit
local saddr               = string_ext.addr

local thread_mgr          = hive.get("thread_mgr")

local HttpServer          = class()
local prop                = property(HttpServer)
prop:reader("listener", nil)        --网络连接对象
prop:reader("ip", nil)              --http server地址
prop:reader("port", 8080)           --http server端口
prop:reader("clients", {})          --clients
prop:reader("requests", {})         --requests
prop:reader("get_handlers", {})     --get_handlers
prop:reader("put_handlers", {})     --put_handlers
prop:reader("del_handlers", {})     --del_handlers
prop:reader("post_handlers", {})    --post_handlers

function HttpServer:__init(http_addr)
    self:setup(http_addr)
end

function HttpServer:setup(http_addr)
    self.ip, self.port = saddr(http_addr)
    local socket       = Socket(self)
    if not socket:listen(self.ip, self.port) then
        log_info("[HttpServer][setup] now listen %s failed", http_addr)
        signalquit(1)
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
    log_debug("[HttpServer][on_socket_accept] client(token:%s) connected!", token)
    self.clients[token] = socket
end

function HttpServer:on_socket_recv(socket, token)
    local request = self.requests[token]
    if not request then
        request = lhttp.create_request()
        log_debug("[HttpServer][on_socket_recv] create_request(token:%s)!", token)
        self.requests[token] = request
    end
    local buf = socket:get_recvbuf()
    local ret_len = request:append(buf)
    if #buf == 0 or ret_len == 0 then
        log_warn("[HttpServer][on_socket_recv] http request append failed, close client(token:%s)!", token)
        self:response(socket, 400, request, "this http request parse error!")
        return
    end
    socket:pop(#buf)
    request:process()
    local state = request:state()
    if state == HTTP_REQUEST_ERROR then
        log_warn("[HttpServer][on_socket_recv] http request process failed, close client(token:%s)!", token)
        self:response(socket, 400, request, "this http request parse error!")
        return
    end
    if state ~= HTTP_SESSION_FINISH then
        log_err("[HttpServer][on_socket_recv] the state is not finish:%s,token:%s", state, token)
        return
    end
    thread_mgr:fork(function()
        local url     = request:url()
        local method  = request:method()
        local headers = request:headers()
        if method == "GET" then
            local querys = request:querys()
            return self:on_http_request(self.get_handlers, socket, request, url, querys, headers)
        end
        if method == "POST" then
            local body = request:body()
            return self:on_http_request(self.post_handlers, socket, request, url, body, headers)
        end
        if method == "PUT" then
            local body = request:body()
            return self:on_http_request(self.put_handlers, socket, request, url, body, headers)
        end
        if method == "DELETE" then
            local querys = request:querys()
            return self:on_http_request(self.del_handlers, socket, request, url, querys, headers)
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
function HttpServer:build_response(status, body, headers)
    local response = lhttp.create_response()
    if type(body) == "table" then
        body = json_encode(body)
    end
    response:set_body(body)
    response:set_status(status)
    for name, value in pairs(headers or {}) do
        response:set_header(name, value)
    end
    return response
end

--http post 回调
function HttpServer:on_http_request(handlers, socket, request, url, ...)
    local handler_info = handlers[url] or handlers["*"]
    if handler_info then
        local handler, target = tunpack(handler_info)
        if not target then
            if type(handler) == "function" then
                local ok, response = pcall(handler, url, ...)
                if not ok then
                    response = { code = 1, msg = response }
                end
                self:response(socket, 200, request, response)
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
                self:response(socket, 200, request, response)
                return
            end
        end
    end
    log_err("[HttpServer][on_http_request] request %s hasn't process!", url)
    self:response(socket, 404, request, "this http request hasn't process!")
end

function HttpServer:response(socket, status, request, hresponse)
    local token = socket:get_token()
    if not token then
        return
    end
    self.requests[token] = nil
    if type(hresponse) == "userdata" then
        socket:send(hresponse:respond(request))
        socket:close()
        return
    end
    local ttype = "text/plain"
    if type(hresponse) == "table" then
        hresponse = json_encode(hresponse)
        ttype     = "application/json"
    end
    socket:send(request:response(status, ttype, hresponse or ""))
    socket:close()
end

return HttpServer
