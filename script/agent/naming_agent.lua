--naming_agent.lua
import("driver/nacos.lua")

--local qget      = hive.get

--local nacos     = qget("nacos")

local NamingAgent = singleton()
function NamingAgent:__init()
end

--节点上线
function NamingAgent:online()
end

--节点下线
function NamingAgent:offline()
end

--查询路由信息
function NamingAgent:find_router()
end

hive.naming_agent = NamingAgent()

return NamingAgent
