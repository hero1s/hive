--webhook.lua

local env_get     = environ.get
local sformat     = string.format
local sfind       = string.find
local json_encode = hive.json_encode

local LIMIT_COUNT = 3    -- 周期内最大次数

local http_client = hive.get("http_client")
local thread_mgr  = hive.get("thread_mgr")
local update_mgr  = hive.get("update_mgr")
local HOUR_S      = hive.enum("PeriodTime", "HOUR_S")

local Webhook     = singleton()
local prop        = property(Webhook)
prop:reader("url", nil)             --url地址
prop:reader("interface", nil)       --通知接口
prop:reader("notify_limit", {})     --控制同样消息的发送频率
prop:reader("lan_ip", "")

function Webhook:__init()
    if env_get("HIVE_LARK_URL") then
        return self:setup(env_get("HIVE_LARK_URL"), "lark_log")
    end
    if env_get("HIVE_DING_URL") then
        return self:setup(env_get("HIVE_DING_URL"), "ding_log")
    end
    if env_get("HIVE_WECHAT_URL") then
        return self:setup(env_get("HIVE_WECHAT_URL"), "wechat_log")
    end
    -- 退出通知
    update_mgr:attach_quit(self)
end

function Webhook:on_quit()
    self.interface = nil
    logger.set_webhook(nil)
end

function Webhook:setup(url, interface)
    self.lan_ip    = hive.lan_ip
    self.url       = url
    self.interface = interface
    if sfind(self.url, "http") then
        logger.set_webhook(self)
    end
end

--飞书
function Webhook:lark_log(title, context)
    local text = sformat("service:%s \n %s \n %s", hive.name, title, context)
    local body = { msg_type = "text", content = { text = text } }
    thread_mgr:fork(function()
        http_client:call_post(self.url, json_encode(body))
    end)
end

--企业微信
--at_members: 成员列表，数组，如 at_members = {"wangqing", "@all"}
--at_mobiles: 手机号列表，数组, 如 at_mobiles = {"156xxxx8827", "@all"}
function Webhook:wechat_log(title, context, at_mobiles, at_members)
    local text = sformat("service:%s \n %s \n %s", hive.name, title, context)
    local body = { msgtype = "text", text = { content = text, mentioned_list = at_members, mentioned_mobile_list = at_mobiles } }
    thread_mgr:fork(function()
        http_client:call_post(self.url, json_encode(body))
    end)
end

--钉钉
--at_all: 是否群at，如 at_all = false/false
--at_mobiles: 手机号列表，数组, 如 at_mobiles = {"189xxxx8325", "156xxxx8827"}
function Webhook:ding_log(title, context, at_mobiles, at_all)
    local text = sformat("service:%s \n %s \n %s", hive.name, title, context)
    local body = { msgtype = "text", text = { content = text }, at = { atMobiles = at_mobiles, isAtAll = at_all } }
    thread_mgr:fork(function()
        http_client:call_post(self.url, json_encode(body))
    end)
end

function Webhook:notify(title, context, ...)
    title           = title .. " host:" .. self.lan_ip
    local interface = self.interface
    if interface then
        local now    = hive.now
        local notify = self.notify_limit[context]
        if not notify then
            notify                     = { time = now, count = 0 }
            self.notify_limit[context] = notify
        end
        if now - notify.time > HOUR_S then
            notify = { time = now, count = 0 }
        end
        if notify.count > LIMIT_COUNT then
            return
        end
        notify.count = notify.count + 1
        self[interface](self, title, context, ...)
    end
end

hive.oanotify = Webhook()

return Webhook
