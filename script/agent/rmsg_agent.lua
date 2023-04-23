--chat_agent.lua
local ReliableMsg = import("store/reliable_msg.lua")
local config_mgr  = hive.get("config_mgr")

local RmsgAgent   = singleton()
local prop        = property(RmsgAgent)
prop:accessor("rmsgs", {})

function RmsgAgent:__init()
    self:setup()
end

function RmsgAgent:setup()
    local rmsg_db = config_mgr:init_table("rmsg", "rmsg_type")
    for id, conf in rmsg_db:iterator() do
        self.rmsgs[id] = ReliableMsg(conf.db_name, conf.table_name, conf.due_days)
    end
end

function RmsgAgent:build_index()
    for _, rmsg in pairs(self.rmsgs or {}) do
        rmsg:build_index()
    end
end

function RmsgAgent:list_message(rmsg_type, to)
    return self.rmsgs[rmsg_type]:list_message(to)
end

function RmsgAgent:send_message(rmsg_type, from, to, body, typ, id)
    return self.rmsgs[rmsg_type]:send_message(from, to, body, typ or rmsg_type, id)
end

function RmsgAgent:delete_message(rmsg_type, to, timestamp)
    return self.rmsgs[rmsg_type]:delete_message(to, timestamp)
end

function RmsgAgent:delete_message_by_uuid(rmsg_type, uuid)
    return self.rmsgs[rmsg_type]:delete_message_by_uuid(uuid)
end

-- export
hive.rmsg_agent = RmsgAgent()

return RmsgAgent
