--nacos.lua
import("network/http_client.lua")
local lcrypt        = require("lcrypt")

local qget          = hive.get
local log_err       = logger.err
local log_info      = logger.info
local lmd5          = lcrypt.md5
local tconcat       = table.concat
local sformat       = string.format
local json_decode   = hive.json_decode
local json_encode   = hive.json_encode

local http_client   = qget("http_client")
local thread_mgr    = qget("thread_mgr")

local WORD_SEPARATOR    = "\x02"
local LINE_SEPARATOR    = "\x01"
local LISTEN_TIMEOUT    = 30000

local Nacos = singleton()
local prop = property(Nacos)
prop:reader("host", nil)            --host
prop:reader("enable", false)        --enable
prop:reader("config_url", nil)      --config url
prop:reader("listen_url", nil)      --listen url
prop:reader("service_url", nil)     --services url
prop:reader("instance_url", nil)    --instance url
prop:reader("namespace_url", nil)   --namespace url
prop:reader("inst_beat_url", nil)   --instance beat url
prop:reader("instances_url", nil)   --instance list url
prop:reader("services_url", nil)    --services list url
prop:accessor("cluster", "")        --service cluster name
prop:accessor("namespace", "")      --service namespace id
prop:accessor("listen_configs", {}) --service namespace id

function Nacos:__init()
    local ip, port =  environ.addr("HIVE_NACOS_ADDR")
    if ip and port then
        self.enable = true
        self.host = environ.get("HIVE_HOST_IP")
        self.config_url = sformat("http://%s:%s/nacos/v1/cs/configs", ip, port)
        self.service_url = sformat("http://%s:%s/nacos/v1/ns/service", ip, port)
        self.instance_url = sformat("http://%s:%s/nacos/v1/ns/instance", ip, port)
        self.listen_url = sformat("http://%s:%s/nacos/v1/cs/configs/listener", ip, port)
        self.services_url = sformat("http://%s:%s/nacos/v1/ns/service/list", ip, port)
        self.instances_url = sformat("http://%s:%s/nacos/v1/ns/instance/list", ip, port)
        self.inst_beat_url = sformat("http://%s:%s/nacos/v1/ns/instance/beat", ip, port)
        self.namespace_url = sformat("http://%s:%s/nacos/v1/console/namespaces", ip, port)
        log_info("[Nacos][setup] setup (%s) success!", self.addr)
    end
end

--config
--------------------------------------------------------------
-- ??????????????????
function Nacos:get_config(data_id, group)
    local query = {
        dataId = data_id,
        tenant = self.namespace,
        group = group or "DEFAULT_GROUP"
    }
    local ok, status, res = http_client:call_get(self.config_url, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][get_config] failed! data_id: %s, code: %s, err: %s", data_id, status, res)
        return nil, res
    end
    return res
end

-- ????????????
function Nacos:modify_config(data_id, content, group)
    local query = {
        dataId = data_id,
        content = content,
        tenant = self.namespace,
        group = group or "DEFAULT_GROUP"
    }
    local ok, status, res = http_client:call_post(self.config_url, nil, nil, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][modify_config] failed! data_id: %s, code: %s, err: %s", data_id, status, res)
        return false, res
    end
    return true
end

-- ????????????
function Nacos:listen_config(data_id, group, on_changed)
    local md5 = ""
    local rgroup = group or "DEFAULT_GROUP"
    local lkey = sformat("%s_%s", data_id, rgroup)
    local headers = {["Long-Pulling-Timeout"] = LISTEN_TIMEOUT }
    self.listen_configs[lkey] = on_changed
    thread_mgr:fork(function()
        while self.listen_configs[lkey] do
            local datas = { data_id, rgroup, md5, self.namespace }
            local lisfmt = sformat("Listening-Configs=%s%s", tconcat(datas, WORD_SEPARATOR), LINE_SEPARATOR)
            local ok, status, res = http_client:call_post(self.listen_url, lisfmt, headers, nil, LISTEN_TIMEOUT + 1000)
            if not ok or status ~= 200 then
                log_err("[Nacos][listen_config] failed! data_id: %s, code: %s, err: %s", data_id, status, res)
                thread_mgr:sleep(2000)
                goto contione
            end
            if res and #res > 0 then
                local value = self:get_config(data_id, rgroup)
                if value then
                    md5 = lmd5(value, 1)
                    on_changed(data_id, rgroup, value)
                end
            end
            :: contione ::
        end
    end)
end

-- ????????????
function Nacos:del_config(data_id, group)
    local query = {
        dataId = data_id,
        tenant = self.namespace,
        group = group or "DEFAULT_GROUP"
    }
    local ok, status, res = http_client:call_del(self.config_url, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][del_config] failed! data_id: %s, code: %s, err: %s", data_id, status, res)
        return false, res
    end
    return true
end

--namespace
--------------------------------------------------------------
-- ????????????????????????
function Nacos:query_namespaces()
    local ok, status, res = http_client:call_get(self.namespace_url)
    if not ok or status ~= 200 then
        log_err("[Nacos][query_namespaces] failed! code: %s, err: %s", status, res)
        return nil, res
    end
    local resdata = json_decode(res)
    return resdata.data
end

--??????????????????
--ns_id     string/????????????ID
--ns_name   string/???????????????
--ns_desc   string/??????????????????
function Nacos:create_namespace(ns_id, ns_name, ns_desc)
    local query = {
        namespaceName = ns_name,
        customNamespaceId = ns_id,
        namespaceDesc = ns_desc or ""
    }
    local ok, status, res = http_client:call_post(self.namespace_url, nil, nil, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][create_namespace] failed! ns_name: %s, code: %s, err: %s", ns_name, status, res)
        return false, res
    end
    return true
end

--??????????????????
--namespace     string/????????????ID
--namespaceShowName string/???????????????
--namespaceDesc string/??????????????????
function Nacos:modify_namespace(ns_id, ns_name, ns_desc)
    local query = {
        namespace = ns_id,
        namespaceShowName = ns_name,
        namespaceDesc = ns_desc or ""
    }
    local ok, status, res = http_client:call_put(self.namespace_url, nil, nil, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][modify_namespace] failed! ns_name: %s, code: %s, err: %s", ns_name, status, res)
        return false, res
    end
    return true
end

--??????????????????
function Nacos:del_namespace(ns_id)
    local query = { namespaceId = ns_id }
    local ok, status, res = http_client:call_del(self.namespace_url, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][del_namespace] failed! ns_id: %s, code: %s, err: %s", ns_id, status, res)
        return false, res
    end
    return true
end

--instance
--------------------------------------------------------------
-- ??????????????????
--namespaceId   string/????????????ID/??????
--clusters      string/???????????????????????????
--serviceName   string/?????????
--groupName     string/?????????
--healthyOnly   boolean/???????????????????????????
function Nacos:query_instances(service_name, group_name)
    local query = {
        clusters = self.cluster,
        namespaceId = self.namespace,
        serviceName = service_name,
        groupName = group_name or ""
    }
    local ok, status, res = http_client:call_get(self.instances_url, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][query_instances] failed! service_name:%s, code: %s, err: %s", service_name, status, res)
        return nil, res
    end
    local jsondata = json_decode(res)
    return jsondata.hosts
end

-- ??????????????????
--ip            string/????????????IP/??????
--port          int/????????????port/??????
--serviceName   string/?????????/??????
--namespaceId   string/????????????ID
--cluster       string/?????????
--groupName     string/?????????
--healthyOnly   boolean/???????????????????????????
--ephemeral     boolean/??????????????????
function Nacos:query_instance(service_name, port, group_name)
    local query = {
        cluster = self.cluster,
        namespaceId = self.namespace,
        serviceName = service_name,
        groupName = group_name or "",
        ip = self.host, port = port
    }
    local ok, status, res = http_client:call_get(self.instance_url, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][query_instance] failed! service_name:%s, code: %s, err: %s", service_name, status, res)
        return nil, res
    end
    return json_decode(res)
end

--????????????
--ip            string/????????????IP/??????
--port          int/????????????port/??????
--namespaceId   string/????????????ID
--weight        double/??????
--enabled       boolean/????????????
--healthy       boolean/????????????
--metadata      string/????????????
--clusterName   string/?????????
--serviceName   string/?????????/??????
--groupName     string/?????????
--ephemeral     boolean/??????????????????
function Nacos:regi_instance(service_name, port, group_name)
    local query = {
        weight = 1,
        serviceName = service_name,
        clusterName = self.cluster,
        namespaceId = self.namespace,
        groupName = group_name or "",
        ip = self.host, port = port,
        ephemeral = true, enabled = false, healthy = true
    }
    local ok, status, res = http_client:call_post(self.instance_url, nil, nil, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][regi_instance] failed! service_name:%s, code: %s, err: %s", service_name, status, res)
        return false, res
    end
    return res
end

--??????????????????
--serviceName   string/?????????
--groupName     string/?????????
--beat          JSON???????????????/??????????????????
--beat          {serviceName:x, cluster:x,ip:x,port:x}
function Nacos:sent_beat(service_name, port, group_name)
    local beat_info = {
        ip = self.host, port = port,
        serviceName = service_name,
        groupName = group_name
    }
    local query = {
        serviceName = service_name,
        groupName = group_name or "",
        namespaceId = self.namespace,
        beat = json_encode(beat_info)
    }
    local ok, status, res = http_client:call_put(self.inst_beat_url, nil, nil, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][sent_beat] failed! service_name: %s, code: %s, err: %s", service_name, status, res)
        return false, res
    end
    return res
end

--????????????
--ip            string/????????????IP/??????
--port          int/????????????port/??????
--namespaceId   string/????????????ID
--weight        double/??????
--enabled       boolean/????????????
--healthy       boolean/????????????
--metadata      string/????????????
--clusterName   string/?????????
--serviceName   string/?????????/??????
--groupName     string/?????????
--ephemeral     boolean/??????????????????
function Nacos:modify_instance(service_name, port, group_name)
    local query = {
        clusterName = self.cluster,
        namespaceId = self.namespace,
        ip = self.host, port = port,
        serviceName = service_name,
        groupName = group_name or "",
    }
    local ok, status, res = http_client:call_put(self.instance_url, nil, nil, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][modify_instance] failed! service_name:%s, code: %s, err: %s", service_name, status, res)
        return false, res
    end
    return res
end

--????????????
function Nacos:del_instance(service_name, port, group_name)
    local query = {
        clusterName = self.cluster,
        namespaceId = self.namespace,
        ip = self.host, port = port,
        serviceName = service_name,
        groupName = group_name or "",
    }
    local ok, status, res = http_client:call_del(self.instance_url, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][del_instance] failed! service_name:%s, code: %s, err: %s", service_name, status, res)
        return false, res
    end
    return res
end

--service
--------------------------------------------------------------
-- ????????????
--service_name  string/?????????/??????
--group_name    string/?????????
--namespaceId   string/????????????ID
--metadata      string/?????????
--selector      string/json/????????????
--protectThreshold  double/????????????,??????0???1,??????0
function Nacos:create_service(service_name, group_name)
    local query = {
        serviceName = service_name,
        groupName = group_name or "",
        namespaceId = self.namespace,
        protectThreshold = 0,
    }
    local ok, status, res = http_client:call_post(self.service_url, nil, nil, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][create_service] failed! service_name: %s, code: %s, err: %s", service_name, status, res)
        return false, res
    end
    return true
end

-- ????????????
--serviceName   string/?????????/??????
--groupName     string/?????????
--namespaceId   string/????????????ID
--metadata      string/?????????
--selector      string/json/????????????
--protectThreshold  double/????????????,??????0???1,??????0
function Nacos:modify_service(service_name, group_name)
    local query = {
        serviceName = service_name,
        groupName = group_name or "",
        namespaceId = self.namespace,
        protectThreshold = 0,
    }
    local ok, status, res = http_client:call_put(self.service_url, nil, nil, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][modify_service] failed! service_name: %s, code: %s, err: %s", service_name, status, res)
        return false, res
    end
    return true
end

-- ????????????
function Nacos:del_service(service_name, group_name)
    local query = {
        serviceName = service_name,
        groupName = group_name or "",
        namespaceId = self.namespace,
    }
    local ok, status, res = http_client:call_del(self.service_url, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][del_service] failed! service_name: %s, code: %s, err: %s", service_name, status, res)
        return false, res
    end
    return true
end

-- ????????????
function Nacos:query_service(service_name, group_name)
    local query = {
        serviceName = service_name,
        groupName = group_name or "",
        namespaceId = self.namespace,
    }
    local ok, status, res = http_client:call_get(self.service_url, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][query_service] failed! service_name: %s, code: %s, err: %s", service_name, status, res)
        return nil, res
    end
    return json_decode(res)
end

-- ??????????????????
-- pageNo       int/????????????
-- pageSize     int/????????????
--group_name    string/?????????
--namespaceId   string/????????????ID
function Nacos:query_services(page, size, group_name)
    local query = {
        pageNo = page,
        pageSize = size,
        groupName = group_name or "",
        namespaceId = self.namespace,
    }
    local ok, status, res = http_client:call_get(self.services_url, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][query_services] failed! group_name: %s, code: %s, err: %s", group_name, status, res)
        return nil, res
    end
    return json_decode(res)
end

hive.nacos = Nacos()

return Nacos
