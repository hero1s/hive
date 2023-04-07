--httpClient.lua
local lcurl             = require("lcurl")

local pairs             = pairs
local log_err           = logger.err
local tconcat           = table.concat
local sformat           = string.format
local hxpcall           = hive.xpcall
local luencode          = lcurl.url_encode
local json_encode       = hive.json_encode

local env_get           = environ.get

local curlm_mgr         = lcurl.curlm_mgr
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
    --创建管理器
    curlm_mgr.on_respond = function(curl_handle, result)
        hxpcall(self.on_respond, "on_respond: %s", self, curl_handle, result)
    end
    self.ca_path         = env_get("HIVE_CA_PATH")
end

function HttpClient:on_quit()
    self.contexts = {}
    curlm_mgr.destory()
end

function HttpClient:on_frame(clock_ms)
    if next(self.contexts) then
        curlm_mgr.update()
        --清除超时请求
        for handle, context in pairs(self.contexts) do
            if clock_ms >= context.time then
                self.contexts[handle] = nil
            end
        end
    end
end

function HttpClient:on_respond(curl_handle, result)
    local context = self.contexts[curl_handle]
    if context then
        local request            = context.request
        local session_id         = context.session_id
        local content, code, err = request.get_respond()
        if result == 0 then
            thread_mgr:response(session_id, true, code, content)
        else
            thread_mgr:response(session_id, false, code, err)
        end
        self.contexts[curl_handle] = nil
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

--构建请求
function HttpClient:send_request(url, timeout, querys, headers, method, datas)
    local to                   = timeout or HTTP_CALL_TIMEOUT
    local fmt_url              = self:format_url(url, querys)
    local request, curl_handle = curlm_mgr.create_request(fmt_url, to)
    if not request then
        log_err("[HttpClient][send_request] failed : %s", curl_handle)
        return false
    end

    -- enable ssl verify
    if self.ca_path and url[5] == "s" then
        request.enable_ssl(self.ca_path)
    end

    if not headers then
        headers = { ["Content-Type"] = "text/plain" }
    end
    if type(datas) == "table" then
        datas                   = json_encode(datas)
        headers["Content-Type"] = "application/json"
    end
    for key, value in pairs(headers or {}) do
        request.set_header(sformat("%s:%s", key, value))
    end
    local ok, err = request[method](datas or "")
    if not ok then
        log_err("[HttpClient][send_request] curl %s failed: %s!", method, err)
        return false
    end
    local session_id           = thread_mgr:build_session_id()
    self.contexts[curl_handle] = {
        request    = request,
        session_id = session_id,
        time       = hive.clock_ms + to,
    }
    return thread_mgr:yield(session_id, url, to)
end

--get接口
function HttpClient:call_get(url, querys, headers, datas, timeout)
    return self:send_request(url, timeout, querys, headers, "call_get", datas)
end

--post接口
function HttpClient:call_post(url, datas, headers, querys, timeout)
    return self:send_request(url, timeout, querys, headers, "call_post", datas)
end

--put接口
function HttpClient:call_put(url, datas, headers, querys, timeout)
    return self:send_request(url, timeout, querys, headers, "call_put", datas)
end

--del接口
function HttpClient:call_del(url, querys, headers, timeout)
    return self:send_request(url, timeout, querys, headers, "call_del")
end

hive.http_client = HttpClient()

return HttpClient
