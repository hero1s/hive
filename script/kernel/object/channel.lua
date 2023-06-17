--channel.lua
local tinsert      = table.insert
local check_failed = hive.failed

local thread_mgr   = hive.get("thread_mgr")

local RPC_TIMEOUT  = hive.enum("NetwkTime", "RPC_CALL_TIMEOUT")

local Channel      = class()
local prop         = property(Channel)
prop:reader("title", "")
prop:reader("executers", {})    --执行器列表

function Channel:__init(title)
    self.title = title or "channel"
end

function Channel:clear()
    self.executers = {}
end

function Channel:empty()
    return #self.executers == 0
end

--添加执行器
-- executer失败返回 false, err
-- executer成功返回 true, code, data
function Channel:push(executer)
    tinsert(self.executers, executer)
end

--执行
function Channel:execute(all_back)
    local all_datas = {}
    local count     = #self.executers
    if count == 0 then
        return true, all_datas
    end
    local success    = true
    local session_id = thread_mgr:build_session_id()
    for i, executer in ipairs(self.executers) do
        local ok, corerr, data = true, 0
        thread_mgr:fork(function()
            ok, corerr, data = executer()
            all_datas[i]     = data
            count            = count - 1
            thread_mgr:try_response(session_id, ok, corerr)
        end)
        local efailed, code = check_failed(corerr, ok)
        if efailed then
            success = efailed
            if not all_back then
                return false, code
            end
        end
    end
    while count > 0 do
        local sok, corerr   = thread_mgr:yield(session_id, self.title, RPC_TIMEOUT)
        local efailed, code = check_failed(corerr, sok)
        if efailed then
            success = efailed
            if not all_back then
                return false, code
            end
        end
    end
    return success, all_datas
end

return Channel
