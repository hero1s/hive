--http_server.lua
local Socket            = import("driver/socket.lua")

local type              = type
local log_warn          = logger.warn
local log_info          = logger.info
local log_debug         = logger.debug
local log_err           = logger.err
local tunpack           = table.unpack
local signal_quit       = signal.quit
local saddr             = string_ext.addr

local HTTP_CALL_TIMEOUT = hive.enum("NetwkTime", "HTTP_CALL_TIMEOUT")

local HttpServer        = class()
local prop              = property(HttpServer)
prop:reader("listener", nil)        --网络连接对象
prop:reader("ip", nil)              --http server地址
prop:reader("port", 8080)           --http server端口
prop:reader("codec", nil)           --codec
prop:reader("listener", nil)        --网络连接对象
prop:reader("clients", {})          --clients
prop:reader("get_handlers", {})     --get_handlers
prop:reader("put_handlers", {})     --put_handlers
prop:reader("del_handlers", {})     --del_handlers
prop:reader("post_handlers", {})    --post_handlers
prop:accessor("limit_ips", nil)
prop:reader("qps_counter", nil)

function HttpServer:__init(http_addr, induce)
    local jcodec = json.jsoncodec()
    self.codec   = codec.httpcodec(jcodec)
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
    self.listener    = socket
    self.qps_counter = hive.make_sampling("http_qps")
end

function HttpServer:close(token, socket)
    self.clients[token] = nil
    socket:close()
end

function HttpServer:on_socket_error(socket, token, err)
    if socket == self.listener then
        log_info("[HttpServer][on_socket_error] listener(%s:%s) close!", self.ip, self.port)
        self.listener = nil
        return
    end
    self.clients[token] = nil
end

function HttpServer:on_socket_accept(socket, token)
    local ip = socket.ip
    if self.limit_ips and self.limit_ips[ip] == nil then
        log_warn("[HttpServer][on_socket_accept] limit white ip visit:%s", ip)
        socket:close()
        return
    end
    self.clients[token] = socket
    socket:set_codec(self.codec)
end

function HttpServer:on_socket_recv(socket, method, url, params, headers, body)
    log_debug("[HttpServer][on_socket_recv] recv:[%s][%s],params:%s,headers:%s,body:%s", method, url, params, headers, body)
    if method == "GET" then
        return self:on_http_request(self.get_handlers, socket, url, params, headers)
    end
    if method == "POST" then
        return self:on_http_request(self.post_handlers, socket, url, body, params, headers)
    end
    if method == "PUT" then
        return self:on_http_request(self.put_handlers, socket, url, body, params, headers)
    end
    if method == "DELETE" then
        return self:on_http_request(self.del_handlers, socket, url, params, headers)
    end
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
    self.qps_counter:count_increase()
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
    if not headers then
        headers = { ["Content-Type"] = "application/json" }
    end
    if type(response) == "string" then
        local html              = response:find("<html")
        headers["Content-Type"] = html and "text/html" or "text/plain"
    end
    socket:send_data(status, headers, response)
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
