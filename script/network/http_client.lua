--httpClient.lua
local lcurl             = require("lcurl")
local ljson             = require("lcjson")

local pairs             = pairs
local log_err           = logger.err
local tunpack           = table.unpack
local tconcat           = table.concat
local sformat           = string.format
local lquery            = lcurl.query
local luencode          = lcurl.url_encode
local lcrequest         = lcurl.create_request
local jencode           = ljson.encode

local thread_mgr        = hive.get("thread_mgr")
local update_mgr        = hive.get("update_mgr")

local HTTP_CALL_TIMEOUT = hive.enum("NetwkTime", "HTTP_CALL_TIMEOUT")

local HttpClient        = singleton()
local prop              = property(HttpClient)
prop:reader("contexts", {})

function HttpClient:__init()
    --加入帧更新
    update_mgr:attach_frame(self)
    --退出通知
    update_mgr:attach_quit(self)
end

function HttpClient:on_quit()
    self.contexts = {}
    lcurl.destory()
end

function HttpClient:on_frame()
    local curl_handle, result = lquery()
    while curl_handle do
        --查询请求结果
        local context = self.contexts[curl_handle]
        if context then
            local request      = context.request
            local session_id   = context.session_id
            local content, err = request:get_respond()
            local info         = request:get_info()
            if result == 0 then
                thread_mgr:response(session_id, true, info.code, content)
            else
                thread_mgr:response(session_id, false, info.code, err)
            end
            self.contexts[curl_handle] = nil
        end
        curl_handle, result = lquery()
    end
    --清除超时请求
    local now_ms = hive.now_ms
    for handle, context in pairs(self.contexts) do
        if now_ms >= context.time then
            self.contexts[handle] = nil
        end
    end
end

function HttpClient:format_url(url, query)
    local qtype = type(query)
    if qtype == "string" and #query > 0 then
        return sformat("%s?%s", url, query)
    end
    if qtype == "table" and next(query) then
        local fquery = {}
        for key, value in pairs(query) do
            fquery[#fquery + 1] = sformat("%s=%s", luencode(key), luencode(value))
        end
        return sformat("%s?%s", url, tconcat(fquery, "&"))
    end
    return url
end

--格式化headers
function HttpClient:format_headers(request, headers)
    if next(headers) then
        local fmt_headers = {}
        for key, value in pairs(headers) do
            fmt_headers[#fmt_headers + 1] = sformat("%s:%s", key, value)
        end
        request:set_headers(tunpack(fmt_headers))
    end
end

--构建请求
function HttpClient:build_request(url, timeout, session_id, headers, method, ...)
    local request, curl_handle = lcrequest(url, timeout)
    if not request then
        log_err("[HttpClient][build_request] failed : %s", curl_handle)
        return
    end
    self:format_headers(request, headers or {})
    local ok, err = request[method](request, ...)
    if not ok then
        log_err("[HttpClient][build_request] curl %s failed: %s!", method, err)
        return false
    end
    self.contexts[curl_handle] = {
        request    = request,
        session_id = session_id,
        time       = hive.now_ms + timeout,
    }
    return true
end

--get接口
function HttpClient:call_get(url, querys, headers, datas, timeout)
    local fmt_url    = self:format_url(url, querys)
    local session_id = thread_mgr:build_session_id()
    if type(datas) == "table" then
        datas                   = jencode(datas)
        headers["Content-Type"] = "application/json"
    end
    local to = timeout or HTTP_CALL_TIMEOUT
    if not self:build_request(fmt_url, to, session_id, headers, "call_get", datas) then
        return false
    end
    return thread_mgr:yield(session_id, url, to)
end

--post接口
function HttpClient:call_post(url, datas, headers, querys, timeout)
    if not headers then
        headers = { ["Content-Type"] = "text/plain" }
    end
    if querys then
        url = self:format_url(url, querys)
    end
    if type(datas) == "table" then
        datas                   = jencode(datas)
        headers["Content-Type"] = "application/json"
    end
    local to         = timeout or HTTP_CALL_TIMEOUT
    local session_id = thread_mgr:build_session_id()
    if not self:build_request(url, to, session_id, headers, "call_post", datas or "") then
        return false
    end
    return thread_mgr:yield(session_id, url, to)
end

--put接口
function HttpClient:call_put(url, datas, headers, querys, timeout)
    if not headers then
        headers = { ["Content-Type"] = "text/plain" }
    end
    if querys then
        url = self:format_url(url, querys)
    end
    if type(datas) == "table" then
        datas                   = jencode(datas)
        headers["Content-Type"] = "application/json"
    end
    local to         = timeout or HTTP_CALL_TIMEOUT
    local session_id = thread_mgr:build_session_id()
    if not self:build_request(url, to, session_id, headers, "call_put", datas or "") then
        return false
    end
    return thread_mgr:yield(session_id, url, to)
end

--del接口
function HttpClient:call_del(url, querys, headers, timeout)
    local to         = timeout or HTTP_CALL_TIMEOUT
    local fmt_url    = self:format_url(url, querys)
    local session_id = thread_mgr:build_session_id()
    if not self:build_request(fmt_url, to, session_id, headers, "call_del") then
        return false
    end
    return thread_mgr:yield(session_id, url, to)
end

hive.http_client = HttpClient()

return HttpClient
