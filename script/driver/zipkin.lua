--zipkin.lua
import("network/http_client.lua")
local lcrypt        = require("lcrypt")

local log_err       = logger.err
local log_info      = logger.info
local sformat       = string.format
local lrandomkey    = lcrypt.randomkey
local lhex_encode   = lcrypt.hex_encode

local thread_mgr    = hive.get("thread_mgr")
local http_client   = hive.get("http_client")

local Zipkin = singleton()
local prop = property(Zipkin)
prop:reader("addr", nil)        --http addr
prop:reader("host", nil)        --host
prop:reader("enable", false)    --enable
prop:reader("spans", {})        --spans
prop:reader("span_indexs", {})  --span_indexs

function Zipkin:__init()
    local ip, port =  environ.addr("HIVE_OPENTRACE_ADDR")
    if ip and port then
        self.enable = true
        self.host = environ.get("HIVE_HOST_IP")
        self.addr = sformat("http://%s:%s/api/v2/spans", ip, port)
        log_info("[Zipkin][setup] setup (%s) success!", self.addr)
    end
end

--https://zipkin.io/zipkin-api/
function Zipkin:general(name, trace_id, parent_id)
    local span_id = self:new_zipkin_id()
    local span = {
        tags = {},
        name = name,
        id = span_id,
        kind = "CLIENT",
        traceId = trace_id,
        parentId = parent_id,
        timestamp = hive.now_ms * 1000,
        annotations = {},
        localEndpoint = {
            serviceName = hive.name,
            ipv4 = self.host
        }
    }
    local trace_span = self.spans[trace_id]
    self.span_indexs[span_id] = trace_id
    if not trace_span then
        self.spans[trace_id] = { }
    end
    trace_span[#trace_span + 1] = span
    log_info("[Zipkin][general] new span name:%s, id:%s, trace_id:%s, parent_id:%s!", name, span_id, trace_id, parent_id)
    return span
end

function Zipkin:new_zipkin_id()
    return lhex_encode(lrandomkey())
end

function Zipkin:new_span(name, trace_id)
    if not trace_id then
        trace_id = self:new_zipkin_id()
    end
    return self:general(name, trace_id)
end

function Zipkin:sub_span(name, parent_id)
    if not parent_id then
        return self:new_span(name)
    end
    local trace_id = self.span_indexs[parent_id]
    if not trace_id then
        return self:new_span(name)
    end
    return self:general(name, trace_id, parent_id)
end

function Zipkin:set_tag(span, tag, value)
    span.tags[tag] = tostring(value)
    span.duration = hive.now_ms * 1000 - span.timestamp
end

function Zipkin:set_annotation(span, value)
    local annotation = {
        value = tostring(value),
        timestamp = hive.now_ms * 1000
    }
    local annotations = span.annotations
    annotations[#annotations + 1] = annotation
    span.duration = hive.now_ms * 1000 - span.timestamp
end

function Zipkin:recovery_span(span)
    span.share = true
    self.span_indexs[span.id] = span.traceId
    self.spans[span.traceId] = { span }
    return span
end

function Zipkin:inject_span(span)
    return {
        id = span.id,
        name = span.name,
        traceId = span.traceId,
        parentId = span.parentId
    }
end

function Zipkin:finish_span(span)
    if self.enable then
        thread_mgr:fork(function()
            local span_list = self.spans[span.traceId]
            for span_id in pairs(span_list) do
                self.span_indexs[span_id] = nil
            end
            local ok, status, res = http_client:call_post(self.addr, span_list)
            if not ok or status >= 300 then
                log_err("[Zipkin][finish_span] post failed! code: %s, err: %s", status, res)
            end
            self.spans[span.traceId] = nil
        end)
    end
end

hive.zipkin = Zipkin()

return Zipkin
