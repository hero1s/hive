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
local jsoncodec         = json.jsoncodec
local httpcodec         = codec.httpcodec
local json_decode       = hive.json_decode

local HTTP_CALL_TIMEOUT = hive.enum("NetwkTime", "HTTP_CALL_TIMEOUT")
local eproto_type       = luabus.eproto_type

local HttpServer        = class()
local prop              = property(HttpServer)
prop:reader("listener", nil)        --网络连接对象
prop:reader("ip", nil)              --http server地址
prop:reader("port", 8080)           --http server端口
prop:reader("hcodec", nil)          --codec
prop:reader("jcodec", nil)          --codec
prop:reader("listener", nil)        --网络连接对象
prop:reader("clients", {})          --clients
prop:reader("handlers", {})         --handlers
prop:accessor("limit_ips", nil)
prop:reader("qps_counter", nil)
prop:accessor("open_log", true)

function HttpServer:__init(http_addr, induce)
    self.jcodec   = jsoncodec()
    self.hcodec   = httpcodec(self.jcodec)
    self.handlers = { GET = {}, POST = {}, PUT = {}, DELETE = {} }
    self:setup(http_addr, induce)
end

function HttpServer:setup(http_addr, induce)
    self.ip, self.port = saddr(http_addr)
    self.port          = induce and (self.port + hive.index - 1) or self.port
    local socket       = Socket(self)
    socket:set_timeout(HTTP_CALL_TIMEOUT)
    if not socket:listen(self.ip, self.port, eproto_type.text) then
        log_err("[HttpServer][setup] now listen {} failed", http_addr)
        signal_quit(1)
        return
    end
    socket:set_codec(self.hcodec)
    log_info("[HttpServer][setup] listen({}:{}) success!", self.ip, self.port)
    self.listener    = socket
    self.qps_counter = hive.make_sampling("http_qps")
end

function HttpServer:close(token, socket)
    self.clients[token] = nil
    socket:close()
end

function HttpServer:on_socket_error(socket, token, err)
    if socket == self.listener then
        log_info("[HttpServer][on_socket_error] listener({}:{}) close!", self.ip, self.port)
        self.listener = nil
        return
    end
    log_debug("[HttpServer][on_socket_error] client(token:{}) close({})!", token, err)
    self.clients[token] = nil
end

function HttpServer:on_socket_accept(socket, token)
    local ip = socket.ip
    if self.limit_ips and self.limit_ips[ip] == nil then
        log_warn("[HttpServer][on_socket_accept] limit white ip visit:{}", ip)
        socket:close()
        return
    end
    self.clients[token] = socket
end

function HttpServer:on_socket_recv(socket, method, url, params, headers, body, jsonable)
    if self.open_log then
        log_debug("[HttpServer][on_socket_recv] recv:[{}][{}],query:{},body:{},head:{},jsonable:{}", method, url, params, body, headers, jsonable)
    end
    local handlers = self.handlers[method]
    if not handlers then
        self:response(socket, 404, "this http method hasn't suppert!")
        return
    end
    self:on_http_request(handlers, socket, url, body, params, headers, jsonable)
end

--注册get回调
function HttpServer:register_get(url, handler, target, decode)
    log_debug("[HttpServer][register_get] url: {}", url)
    self.handlers.GET[url] = { handler, target, decode == nil and true or decode }
end

--注册post回调
function HttpServer:register_post(url, handler, target, decode)
    log_debug("[HttpServer][register_post] url: {}", url)
    self.handlers.POST[url] = { handler, target, decode == nil and true or decode }
end

--注册put回调
function HttpServer:register_put(url, handler, target, decode)
    log_debug("[HttpServer][register_put] url: {}", url)
    self.handlers.PUT[url] = { handler, target, decode == nil and true or decode }
end

--注册del回调
function HttpServer:register_del(url, handler, target, decode)
    log_debug("[HttpServer][register_del] url: {}", url)
    self.handlers.DELETE[url] = { handler, target, decode == nil and true or decode }
end

--http post 回调
function HttpServer:on_http_request(handlers, socket, url, body, params, headers, jsonable)
    self.qps_counter:count_increase()
    local handler_info = handlers[url] or handlers["*"]
    if handler_info then
        local handler, target, decode = tunpack(handler_info)
        if jsonable and decode then
            body = json_decode(body)
        end
        if not target then
            if type(handler) == "function" then
                local ok, response, headers = pcall(handler, url, body, params, headers)
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
                local ok, response, headers = pcall(handler, target, url, body, params, headers)
                if not ok then
                    log_err("[HttpServer][on_http_request] ok:{}, response:{}", ok, response)
                    response = { code = 1, msg = response }
                end
                self:response(socket, 200, response, headers)
                return
            end
        end
    end
    log_warn("[HttpServer][on_http_request] request {} hasn't process!", url)
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
    self.handlers.GET[url]    = nil
    self.handlers.PUT[url]    = nil
    self.handlers.POST[url]   = nil
    self.handlers.DELETE[url] = nil
end

return HttpServer
