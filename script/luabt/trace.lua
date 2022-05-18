--trace.lua
local pairs     = pairs
local log_debug = logger.debug

local FAIL      = luabt.BTConst.FAIL
local SUCCESS   = luabt.BTConst.SUCCESS

local function st2str(status)
    if status == SUCCESS then
        return "SUCCESS"
    elseif status == FAIL then
        return "FAIL"
    else
        return "RUNNING"
    end
end

local BtTrace = class()
function BtTrace:__init(...)
    self.stack = {}
    self.nodes = {}
end

function BtTrace:clear()
    if self.log then
        self.stack = {}
        self.nodes = {}
    end
end

function BtTrace:trace()
    for _, node in pairs(self.stack) do
        log_debug("lua bt stack level:%d, node:%s, status:%s", node.level, node.node.name, node.status)
    end
end

function BtTrace:node_execute(bt, level, node)
    if not self.log then
        return
    end
    local node_info = {
        node  = node,
        level = level,
    }
    self.stack[#self.stack + 1] = node_info
    self.nodes[node] = node_info
end

function BtTrace:node_status(bt, node, status)
    local node_info = self.nodes[node]
    if node_info then
        node_info.status = st2str(status)
    end
end

return BtTrace
