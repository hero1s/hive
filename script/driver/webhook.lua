--webhook.lua
import("network/http_client.lua")

local sformat     = string.format

local http_client = hive.get("http_client")
local update_mgr  = hive.get("update_mgr")

local LIMIT_TIME  = hive.enum("PeriodTime", "MINUTE_10_S")
local LIMIT_COUNT = 5

local Webhook     = singleton()
local prop        = property(Webhook)
prop:reader("hooks", {})            --webhook通知接口
prop:reader("title", "")
prop:reader("notify_limit", {})     --控制同样消息的发送频率

function Webhook:__init()
    self.title            = sformat("[%s][%s][%s]", hive.name, hive.lan_ip, stdfs.current_path())
    self.hooks.lark_log   = environ.get("HIVE_LARK_URL")
    self.hooks.ding_log   = environ.get("HIVE_DING_URL")
    self.hooks.wechat_log = environ.get("HIVE_WECHAT_URL")

    update_mgr:attach_minute(self)
end

--清理过期limit
function Webhook:on_minute()
    self:clear_due_limit()
end

--飞书
function Webhook:lark_log(url, title, context)
    local text = sformat("%s\n %s", title, context)
    local body = { msg_type = "text", content = { text = text } }
    http_client:call_post(url, body)
end

--企业微信
--at_members: 成员列表，数组，如 at_members = {"wangqing", "@all"}
--at_mobiles: 手机号列表，数组, 如 at_mobiles = {"156xxxx8827", "@all"}
function Webhook:wechat_log(url, title, context, at_mobiles, at_members)
    local text = sformat("%s\n %s", title, context)
    local body = { msgtype = "text", text = { content = text, mentioned_list = at_members, mentioned_mobile_list = at_mobiles } }
    http_client:call_post(url, body)
end

--钉钉
--at_all: 是否群at，如 at_all = false/false
--at_mobiles: 手机号列表，数组, 如 at_mobiles = {"189xxxx8325", "156xxxx8827"}
function Webhook:ding_log(url, title, context, at_mobiles, at_all)
    local text = sformat("%s\n %s", title, context)
    local body = { msgtype = "text", text = { content = text }, at = { atMobiles = at_mobiles, isAtAll = at_all } }
    http_client:call_post(url, body)
end

function Webhook:notify(title, content, source, ...)
    if self:count_msg(source, content) then
        if next(self.hooks) then
            title = self.title .. title
            for hook_api, url in pairs(self.hooks) do
                self[hook_api](self, url, title, content, ...)
            end
        end
    end
end

function Webhook:send_log(hook_api, url, title, content, source, ...)
    if self:count_msg(source, content) then
        if self[hook_api] then
            title = self.title .. title
            self[hook_api](self, url, title, content, ...)
        end
    end
end

function Webhook:count_msg(source, content)
    if not source then
        return true
    end
    local now    = hive.now
    local notify = self.notify_limit[source]
    if not notify then
        notify                    = { time = now, count = 0, content = content }
        self.notify_limit[source] = notify
    end
    notify.count = notify.count + 1
    return notify.count < LIMIT_COUNT
end

function Webhook:clear_due_limit()
    for k, v in pairs(self.notify_limit) do
        if v.time + LIMIT_TIME < hive.now then
            self.notify_limit[k] = nil
            if v.count >= LIMIT_COUNT then
                self:notify("", sformat("statistic error msg source:%s,count:%s,content:%s", k, v.count, v.content))
            end
        end
    end
end

hive.webhook = Webhook()

return Webhook
