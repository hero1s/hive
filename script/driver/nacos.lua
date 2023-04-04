--nacos.lua
import("network/http_client.lua")
local ljson          = require("lyyjson")
local lcrypt         = require("lcrypt")

local log_err        = logger.err
local log_info       = logger.info
local lmd5           = lcrypt.md5
local tconcat        = table.concat
local sformat        = string.format
local json_decode    = ljson.decode
local json_encode    = ljson.encode
local mtointeger     = math.tointeger

local event_mgr      = hive.get("event_mgr")
local thread_mgr     = hive.get("thread_mgr")
local update_mgr     = hive.get("update_mgr")
local http_client    = hive.get("http_client")

local WORD_SEPARATOR = "\x02"
local LINE_SEPARATOR = "\x01"
local LISTEN_TIMEOUT = 30000

local Nacos          = singleton()
local prop           = property(Nacos)
prop:reader("host", nil)            --host
prop:reader("enable", false)        --enable
prop:reader("login_url", nil)       --login url
prop:reader("config_url", nil)      --config url
prop:reader("switches_url", nil)    --switch url
prop:reader("listen_url", nil)      --listen url
prop:reader("service_url", nil)     --services url
prop:reader("instance_url", nil)    --instance url
prop:reader("namespace_url", nil)   --namespace url
prop:reader("inst_beat_url", nil)   --instance beat url
prop:reader("instances_url", nil)   --instance list url
prop:reader("services_url", nil)    --services list url
prop:reader("access_token", nil)    --access token
prop:reader("cluster", "")          --service cluster name
prop:reader("nacos_ns", "")         --service namespace id
prop:reader("config_ns", "")        --config namespace id
prop:reader("listen_configs", {})   --listen configs

function Nacos:__init()
    local ip, port  = environ.addr("HIVE_NACOS_ADDR")
    local nacos_ns  = environ.get("HIVE_NACOS_NAMESPACE")
    local config_ns = environ.get("HIVE_CONFIG_NAMESPACE")
    if ip and port and nacos_ns then
        self.enable        = true
        self.nacos_ns      = nacos_ns
        self.cluster       = hive.cluster
        self.config_ns     = config_ns or nacos_ns
        self.login_url     = sformat("http://%s:%s/nacos/v1/auth/login", ip, port)
        self.config_url    = sformat("http://%s:%s/nacos/v1/cs/configs", ip, port)
        self.service_url   = sformat("http://%s:%s/nacos/v1/ns/service", ip, port)
        self.instance_url  = sformat("http://%s:%s/nacos/v1/ns/instance", ip, port)
        self.listen_url    = sformat("http://%s:%s/nacos/v1/cs/configs/listener", ip, port)
        self.switches_url  = sformat("http://%s:%s/nacos/v1/ns/operator/switches", ip, port)
        self.services_url  = sformat("http://%s:%s/nacos/v1/ns/service/list", ip, port)
        self.instances_url = sformat("http://%s:%s/nacos/v1/ns/instance/list", ip, port)
        self.inst_beat_url = sformat("http://%s:%s/nacos/v1/ns/instance/beat", ip, port)
        self.namespace_url = sformat("http://%s:%s/nacos/v1/console/namespaces", ip, port)
        log_info("[Nacos][setup] setup (%s:%s) success!", ip, port)
    end
    --定时获取token
    update_mgr:attach_hour(self)
    thread_mgr:success_call(1000, function()
        return self:auth()
    end)
end

function Nacos:on_hour()
    thread_mgr:success_call(1000, function()
        return self:auth()
    end)
end

-- 登陆
function Nacos:auth()
    local bfirst     = (not self.access_token)
    local auth_args  = environ.get("HIVE_NACOS_AUTH", "")
    local user, pass = string_ext.usplit(auth_args, ":")
    if user and pass then
        local ok, status, res = http_client:call_post(self.login_url, nil, nil, { username = user, password = pass })
        if not ok or status ~= 200 then
            log_err("[Nacos][auth] failed! code: %s, err: %s", status, res)
            return false, res
        end
        local resdata     = json_decode(res)
        self.access_token = resdata.accessToken
        log_info("[Nacos][auth] auth success : %s", res)
    else
        self.access_token = ""
    end
    if bfirst then
        event_mgr:notify_trigger("on_nacos_ready")
    end
    return true
end

--config
--------------------------------------------------------------
-- 获取配置信息
function Nacos:get_config(data_id, group)
    local query           = {
        dataId      = data_id,
        tenant      = self.config_ns,
        accessToken = self.access_token,
        group       = group or "DEFAULT_GROUP"
    }
    local ok, status, res = http_client:call_get(self.config_url, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][get_config] failed! data_id: %s, code: %s, err: %s", data_id, status, res)
        return nil, res
    end
    return res
end

-- 推送配置
function Nacos:modify_config(data_id, content, group)
    local query           = {
        dataId      = data_id,
        content     = content,
        tenant      = self.config_ns,
        accessToken = self.access_token,
        group       = group or "DEFAULT_GROUP"
    }
    local ok, status, res = http_client:call_post(self.config_url, nil, nil, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][modify_config] failed! data_id: %s, code: %s, err: %s", data_id, status, res)
        return false, res
    end
    return true
end

-- 监听配置
function Nacos:listen_config(data_id, group, md5, on_changed)
    md5                       = md5 or ""
    local rgroup              = group or "DEFAULT_GROUP"
    local lkey                = sformat("%s_%s", data_id, rgroup)
    local headers             = { ["Long-Pulling-Timeout"] = LISTEN_TIMEOUT }
    self.listen_configs[lkey] = on_changed
    thread_mgr:fork(function()
        while self.listen_configs[lkey] do
            local query           = { accessToken = self.access_token }
            local datas           = { data_id, rgroup, md5, self.config_ns }
            local lisfmt          = sformat("Listening-Configs=%s%s", tconcat(datas, WORD_SEPARATOR), LINE_SEPARATOR)
            local ok, status, res = http_client:call_post(self.listen_url, lisfmt, headers, query, LISTEN_TIMEOUT + 1000)
            if not ok or status ~= 200 then
                log_err("[Nacos][listen_config] failed! data_id: %s, code: %s, err: %s", data_id, status, res)
                thread_mgr:sleep(2000)
                goto contione
            end
            if res and #res > 0 then
                local value = self:get_config(data_id, rgroup)
                if value then
                    md5 = lmd5(value, 1)
                    on_changed(data_id, rgroup, md5, value)
                end
            end
            :: contione ::
        end
    end)
end

-- 删除配置
function Nacos:del_config(data_id, group)
    local query           = {
        dataId      = data_id,
        tenant      = self.config_ns,
        accessToken = self.access_token,
        group       = group or "DEFAULT_GROUP"
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
-- 查询命名空间列表
function Nacos:query_namespaces()
    local query           = { accessToken = self.access_token }
    local ok, status, res = http_client:call_get(self.namespace_url, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][query_namespaces] failed! code: %s, err: %s", status, res)
        return nil, res
    end
    local resdata = json_decode(res)
    return resdata.data
end

--创建命名空间
--ns_id     string/命名空间ID
--ns_name   string/命名空间名
--ns_desc   string/命名空间描述
function Nacos:create_namespace(ns_id, ns_name, ns_desc)
    local query           = {
        namespaceName     = ns_name,
        customNamespaceId = ns_id,
        namespaceDesc     = ns_desc or "",
        accessToken       = self.access_token
    }
    local ok, status, res = http_client:call_post(self.namespace_url, nil, nil, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][create_namespace] failed! ns_name: %s, code: %s, err: %s", ns_name, status, res)
        return false, res
    end
    return true
end

--修改命名空间
--namespace     string/命名空间ID
--namespaceShowName string/命名空间名
--namespaceDesc string/命名空间描述
function Nacos:modify_namespace(ns_id, ns_name, ns_desc)
    local query           = {
        namespace         = ns_id,
        namespaceShowName = ns_name,
        namespaceDesc     = ns_desc or "",
        accessToken       = self.access_token
    }
    local ok, status, res = http_client:call_put(self.namespace_url, nil, nil, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][modify_namespace] failed! ns_name: %s, code: %s, err: %s", ns_name, status, res)
        return false, res
    end
    return true
end

--删除命名空间
function Nacos:del_namespace(ns_id)
    local query           = {
        namespaceId = ns_id,
        accessToken = self.access_token
    }
    local ok, status, res = http_client:call_del(self.namespace_url, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][del_namespace] failed! ns_id: %s, code: %s, err: %s", ns_id, status, res)
        return false, res
    end
    return true
end

--instance
--------------------------------------------------------------
-- 查询实例列表
--namespaceId   string/命名空间ID/必选
--clusters      string/多个集群用逗号分隔
--serviceName   string/服务名
--groupName     string/分组名
--healthyOnly   boolean/是否只返回健康实例
function Nacos:query_instances(service_name, group_name)
    local query           = {
        clusters    = self.cluster,
        namespaceId = self.nacos_ns,
        serviceName = service_name,
        groupName   = group_name or "",
        accessToken = self.access_token
    }
    local ok, status, res = http_client:call_get(self.instances_url, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][query_instances] failed! service_name:%s, code: %s, err: %s", service_name, status, res)
        return nil, res
    end
    local insts    = {}
    local jsondata = json_decode(res)
    for _, inst in pairs(jsondata.hosts) do
        local id       = tonumber(inst.metadata.id)
        local is_ready = mtointeger(inst.metadata.is_ready)
        insts[id]      = { id = id, is_ready = is_ready, ip = inst.ip, port = inst.port }
    end
    return insts
end

-- 查询实例详情
--ip            string/服务实例IP/必选
--host          string/服务实例host/必选
--port          int/服务实例port/必选
--serviceName   string/服务名/必选
--namespaceId   string/命名空间ID
--cluster       string/集群名
--groupName     string/分组名
--healthyOnly   boolean/是否只返回健康实例
--ephemeral     boolean/是否临时实例
function Nacos:query_instance(service_name, host, port, group_name)
    local query           = {
        cluster     = self.cluster,
        namespaceId = self.nacos_ns,
        serviceName = service_name,
        groupName   = group_name or "",
        accessToken = self.access_token,
        ip          = host, port = port
    }
    local ok, status, res = http_client:call_get(self.instance_url, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][query_instance] failed! service_name:%s, code: %s, err: %s", service_name, status, res)
        return nil, res
    end
    return json_decode(res)
end

--注册实例
--ip            string/服务实例IP/必选
--host          string/服务实例host/必选
--port          int/服务实例port/必选
--namespaceId   string/命名空间ID
--weight        double/权重
--enabled       boolean/是否上线
--healthy       boolean/是否健康
--metadata      string/扩展信息
--clusterName   string/集群名
--serviceName   string/服务名/必选
--groupName     string/分组名
--ephemeral     boolean/是否临时实例
function Nacos:regi_instance(service_name, host, port, group_name, metadata)
    local query = {
        weight      = 1,
        ip          = host, port = port,
        serviceName = service_name,
        clusterName = self.cluster,
        namespaceId = self.nacos_ns,
        groupName   = group_name or "",
        accessToken = self.access_token,
        ephemeral   = false, enabled = false, healthy = true
    }
    if metadata then
        query.metadata = json_encode(metadata)
    end
    local ok, status, res = http_client:call_post(self.instance_url, nil, nil, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][regi_instance] failed! service_name:%s, code: %s, err: %s", service_name, status, res)
        return false, res
    end
    return true
end

--发送实例心跳
--serviceName   string/服务名
--groupName     string/分组名
--host          string/服务实例host/必选
--port          int/服务实例port/必选
--beat          JSON格式字符串/实例心跳内容
--beat          {serviceName:x, cluster:x,ip:x,port:x}
function Nacos:sent_beat(service_name, host, port, group_name)
    local beat_info       = {
        ip          = host, port = port,
        serviceName = service_name,
        groupName   = group_name
    }
    local query           = {
        serviceName = service_name,
        groupName   = group_name or "",
        namespaceId = self.nacos_ns,
        beat        = json_encode(beat_info),
        accessToken = self.access_token
    }
    local ok, status, res = http_client:call_put(self.inst_beat_url, nil, nil, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][sent_beat] failed! service_name: %s, code: %s, err: %s", service_name, status, res)
        return false, res
    end
    return res
end

--修改实例
--ip            string/服务实例IP/必选
--host          string/服务实例host/必选
--port          int/服务实例port/必选
--namespaceId   string/命名空间ID
--weight        double/权重
--enabled       boolean/是否上线
--healthy       boolean/是否健康
--metadata      string/扩展信息
--clusterName   string/集群名
--serviceName   string/服务名/必选
--groupName     string/分组名
--ephemeral     boolean/是否临时实例
function Nacos:modify_instance(service_name, host, port, group_name)
    local query           = {
        ip          = host, port = port,
        clusterName = self.cluster,
        namespaceId = self.nacos_ns,
        serviceName = service_name,
        groupName   = group_name or "",
        accessToken = self.access_token
    }
    local ok, status, res = http_client:call_put(self.instance_url, nil, nil, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][modify_instance] failed! service_name:%s, code: %s, err: %s", service_name, status, res)
        return false, res
    end
    return res
end

--删除实例
function Nacos:del_instance(service_name, host, port, group_name)
    local query           = {
        ip          = host, port = port,
        clusterName = self.cluster,
        namespaceId = self.nacos_ns,
        serviceName = service_name,
        groupName   = group_name or "",
        accessToken = self.access_token
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
-- 创建服务
--service_name  string/服务名/必选
--group_name    string/分组名
--namespaceId   string/命名空间ID
--metadata      string/元数据
--selector      string/json/访问策略
--protectThreshold  double/保护阈值,取值0到1,默认0
function Nacos:create_service(service_name, group_name)
    local query           = {
        serviceName      = service_name,
        groupName        = group_name or "",
        namespaceId      = self.nacos_ns,
        accessToken      = self.access_token,
        protectThreshold = 0,
    }
    local ok, status, res = http_client:call_post(self.service_url, nil, nil, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][create_service] failed! service_name: %s, code: %s, err: %s", service_name, status, res)
        return false, res
    end
    return true
end

-- 修改服务
--serviceName   string/服务名/必选
--groupName     string/分组名
--namespaceId   string/命名空间ID
--metadata      string/元数据
--selector      string/json/访问策略
--protectThreshold  double/保护阈值,取值0到1,默认0
function Nacos:modify_service(service_name, group_name)
    local query           = {
        serviceName      = service_name,
        groupName        = group_name or "",
        namespaceId      = self.nacos_ns,
        accessToken      = self.access_token,
        protectThreshold = 0,
    }
    local ok, status, res = http_client:call_put(self.service_url, nil, nil, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][modify_service] failed! service_name: %s, code: %s, err: %s", service_name, status, res)
        return false, res
    end
    return true
end

-- 删除服务
function Nacos:del_service(service_name, group_name)
    local query           = {
        serviceName = service_name,
        groupName   = group_name or "",
        namespaceId = self.nacos_ns,
        accessToken = self.access_token
    }
    local ok, status, res = http_client:call_del(self.service_url, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][del_service] failed! service_name: %s, code: %s, err: %s", service_name, status, res)
        return false, res
    end
    return true
end

-- 查询服务
function Nacos:query_service(service_name, group_name)
    local query           = {
        serviceName = service_name,
        groupName   = group_name or "",
        namespaceId = self.nacos_ns,
        accessToken = self.access_token
    }
    local ok, status, res = http_client:call_get(self.service_url, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][query_service] failed! service_name: %s, code: %s, err: %s", service_name, status, res)
        return nil, res
    end
    return json_decode(res)
end

-- 查询服务列表
-- pageNo       int/当前页码
-- pageSize     int/分页大小
--group_name    string/分组名
--namespaceId   string/命名空间ID
function Nacos:query_services(page, size, group_name)
    local query           = {
        pageNo      = page or 1,
        pageSize    = size or 50,
        group_name  = group_name or "",
        namespaceId = self.nacos_ns,
        accessToken = self.access_token
    }
    local ok, status, res = http_client:call_get(self.services_url, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][query_services] failed! group_name: %s, code: %s, err: %s", group_name, status, res)
        return nil, res
    end
    local jdata = json_decode(res)
    return jdata.doms
end

-- 查询系统开关
function Nacos:query_switchs()
    local ok, status, res = http_client:call_get(self.switches_url, {})
    if not ok or status ~= 200 then
        log_err("[Nacos][query_switchs] failed! code: %s, err: %s", status, res)
        return nil, res
    end
    return json_decode(res)
end

-- 修改系统开关
function Nacos:modify_switchs(entry, value)
    local query           = {
        entry       = entry, value = value,
        accessToken = self.access_token
    }
    local ok, status, res = http_client:call_put(self.switches_url, nil, nil, query)
    if not ok or status ~= 200 then
        log_err("[Nacos][modify_switchs] failed! entry: %s, code: %s, err: %s", entry, status, res)
        return false, res
    end
    return true
end

hive.nacos = Nacos()

return Nacos
