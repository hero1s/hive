--influx.lua
import("network/http_client.lua")
local ljson         = require("lcjson")
local log_err       = logger.err
local log_info      = logger.info
local json_decode   = ljson.decode
local tconcat       = table.concat
local sgsub         = string.gsub
local sformat       = string.format
local ssplit        = string_ext.split
local serialize     = hive.serialize

local http_client   = hive.get("http_client")
local WEEK_S        = hive.enum("PeriodTime", "WEEK_S")

local Influx = class()
local prop = property(Influx)
prop:reader("org", nil)         --org
prop:reader("bucket", nil)      --bucket
prop:reader("org_addr", nil)    --org_addr
prop:reader("query_addr", nil)  --query_addr
prop:reader("write_addr", nil)  --query_addr
prop:reader("bucket_addr", nil) --bucket_addr
prop:reader("common_headers", nil)

function Influx:__init(ip, port, org, bucket, token)
    self.org = org
    self.bucket = bucket
    self.org_addr = sformat("http://%s:%s/api/v2/orgs", ip, port)
    self.write_addr = sformat("http://%s:%s/api/v2/write", ip, port)
    self.query_addr = sformat("http://%s:%s/api/v2/query", ip, port)
    self.bucket_addr = sformat("http://%s:%s/api/v2/buckets", ip, port)
    self.common_headers = { ["Authorization"] = sformat("Token %s", token), ["Content-type"] = "application/json" }
    log_info("[Influx] influx driver(%s:%s) setup success!", ip, port)
end

--line protocol
--https://docs.influxdata.com/influxdb/v2.1/api/#operation/PostBuckets
local BOOL_STR = { 't', 'T', 'true', 'True', 'TRUE', 'f', 'F', 'false', 'False', 'FALSE' }
function Influx:quote_value(value)
    local vtype = type(value)
    if vtype == "number" or vtype == "bool" then
        return value
    end
    if vtype ~= "string" then
        value = serialize(value)
    end
    for i = 1, 10 do
        if value == BOOL_STR[i] then
            return value
        end
    end
    return sformat('"%s"', sgsub(value, '"', '\\"'))
end

function Influx:quote_field(value)
    return sgsub(sgsub(sgsub(value, '=', '\\='), ',', '\\,'), ' ', '\\ ')
end

function Influx:quote_measurement(value)
    return sgsub(sgsub(value, ',', '\\,'), ' ', '\\ ')
end

function Influx:quote_tags(measurement, tags)
    local qtags = { measurement }
    for key, value in pairs(tags) do
        qtags[#qtags + 1] = sformat("%s=%s", self:quote_field(key), self:quote_field(value))
    end
    return tconcat(qtags, ",")
end

function Influx:quote_fields(fields)
    local qfields = { }
    for key, value in pairs(fields) do
        qfields[#qfields + 1] = sformat("%s=%s", self:quote_field(key), self:quote_value(value))
    end
    return tconcat(qfields, ",")
end

--influx操作接口
--查找bucket信息
function Influx:find_bucket(bucket_name)
    local querys = { name = bucket_name }
    local ok, status, res = http_client:call_get(self.bucket_addr, querys, self.common_headers)
    if not ok or status >= 300 then
        log_err("[Influx][find_bucket] failed! status: %s, err: %s", status, ok and res or status)
        return false, ok and res or status
    end
    local response = json_decode(res)
    local buckets = response.buckets
    if not bucket_name then
        return true, buckets
    end
    for _, bucket in pairs(buckets) do
        if bucket.name == bucket_name then
            return true, bucket
        end
    end
    return false, "bucket not exist"
end

--查找org信息
function Influx:find_org(org_name)
    local querys = { org = org_name }
    local ok, status, res = http_client:call_get(self.org_addr, querys, self.common_headers)
    if not ok or status >= 300 then
        log_err("[Influx][find_org] failed! status: %s, err: %s", status, ok and res or status)
        return false, ok and res or status
    end
    local response = json_decode(res)
    local orgs = response.orgs
    if not org_name then
        return true, orgs
    end
    for _, org in pairs(orgs) do
        if org.name == org_name then
            return true, org
        end
    end
    return false, "org no t exist"
end

--create bucket
function Influx:create_bucket(name, expire_time, description)
    local cur_org = self:find_org(self.org_name)
    if not cur_org then
        log_err("[Influx][create_bucket] org(%s) config error", self.org_name)
        return false, "org config error"
    end
    local data = {
        name = name,
        orgID = cur_org.id,
        description = description,
        retentionRules = {}
    }
    data.retentionRules[1] = {
        type = "expire",
        shardGroupDurationSeconds = 0,
        everySeconds = expire_time or WEEK_S
    }
    local ok, status, res = http_client:call_post(self.bucket_addr, data, self.common_headers)
    if not ok or status >= 300 then
        log_err("[Influx][create_bucket] failed! status: %s, err: %s", status, ok and res or status)
        return false, ok and res or status
    end
    return true, json_decode(res)
end

--delete bucket
function Influx:delete_bucket_by_id(bucket_id)
    local url = sformat("%s/%s", self.bucket_addr, bucket_id)
    local ok, status, res = http_client:call_del(url, {}, self.common_headers)
    if not ok or status >= 300 then
        log_err("[Influx][delete_bucket_by_id] failed! status: %s, err: %s", status, ok and res or status)
        return false, ok and res or status
    end
    return true
end

--delete bucket
function Influx:delete_bucket(bucket_name)
    local bucket = self:find_bucket(bucket_name)
    if not bucket then
        log_err("[Influx][delete_bucket] failed! bucket: %s not exist", bucket_name)
        return false, "bucket not exist"
    end
    local url = sformat("%s/%s", self.bucket_addr, bucket.id)
    local ok, status, res = http_client:call_del(url, {}, self.common_headers)
    if not ok or status >= 300 then
        log_err("[Influx][delete_bucket] failed! status: %s, err: %s", status, ok and res or status)
        return false, ok and res or status
    end
    return true
end

--写数据
function Influx:write(measurement, tags, fields)
    local prefix = self:quote_tags(measurement, tags)
    local suffix = self:quote_fields(fields)
    local line_protocol = sformat("%s %s", prefix, suffix)
    local headers = {
        ["Accept"] = "application/json",
        ["Content-type"] = "text/plain",
        ["Authorization"] = self.common_headers["Authorization"],
    }
    local querys = { org = self.org, bucket = self.bucket }
    local ok, status, res = http_client:call_post(self.write_addr, line_protocol, headers, querys)
    if not ok or status >= 300 then
        log_err("[Influx][write] failed! status: %s, err: %s", status, ok and res or status)
        return false, ok and res or status
    end
    return true
end

--写数据
function Influx:batch(batch_datas)
    local protocols = {}
    for measurement, datas in pairs(batch_datas) do
        local prefix = self:quote_tags(measurement, datas.tags)
        for _, fields in pairs(datas.field_list) do
            local suffix = self:quote_fields(fields)
            protocols[#protocols] = sformat("%s %s", prefix, suffix)
        end
    end
    local line_protocol = tconcat(protocols, "\n")
    local headers = {
        ["Accept"] = "application/json",
        ["Content-type"] = "text/plain",
        ["Authorization"] = self.common_headers["Authorization"],
    }
    local querys = { org = self.org, bucket = self.bucket }
    local ok, status, res = http_client:call_post(self.write_addr, line_protocol, headers, querys)
    if not ok or status >= 300 then
        log_err("[Influx][batch] failed! status: %s, err: %s", status, ok and res or status)
        return false, ok and res or status
    end
    return true
end

--查询
function Influx:query(script)
    local headers = {
        ["Accept"] = "application/csv",
        ["Content-type"] = "application/vnd.flux",
        ["Authorization"] = self.common_headers["Authorization"],
    }
    local querys = { org = self.org }
    local ok, status, res = http_client:call_post(self.query_addr, script, headers, querys)
    if not ok or status >= 300 then
        log_err("[Influx][query] failed! status: %s, err: %s", status, ok and res or status)
        return false, ok and res or status
    end
    return true, self:parse_csv(res)
end

--解析结果
function Influx:parse_csv(value)
    local lines = ssplit(value, "\n")
    if #lines < 2 then
        return
    end
    local res = {}
    local titles = ssplit(lines[1], ",")
    for i = 2, #lines do
        local values = ssplit(lines[i], ",")
        if #values == #titles then
            local record = {}
            for j = 1, #values do
                record[titles[j]] = values[j]
            end
            res[#res + 1] = record
        end
    end
    return res
end

return Influx
