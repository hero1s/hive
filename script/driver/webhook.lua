--webhook.lua
import("network/http_client.lua")

local sformat     = string.format

local http_client = hive.get("http_client")

local Webhook     = singleton()
local prop        = property(Webhook)
prop:reader("hooks", {})            --webhook通知接口
prop:reader("lan_ip", "")

function Webhook:__init()
    self.lan_ip           = hive.lan_ip
    self.hooks.lark_log   = environ.get("HIVE_LARK_URL")
    self.hooks.ding_log   = environ.get("HIVE_DING_URL")
    self.hooks.wechat_log = environ.get("HIVE_WECHAT_URL")
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

function Webhook:notify(title, content, ...)
    if next(self.hooks) then
        title = title .. " host:" .. self.lan_ip
        for hook_api, url in pairs(self.hooks) do
            self[hook_api](self, url, title, content, ...)
        end
    end
end

function Webhook:send_log(hook_api, url, title, content, ...)
    if self[hook_api] then
        title = title .. " host:" .. self.lan_ip
        self[hook_api](self, url, title, content, ...)
    end
end

hive.webhook = Webhook()

return Webhook
