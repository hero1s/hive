--node.lua
local mrandom = math.random
local RUNNING = luabt.BTConst.RUNNING

function luabt.node_execute(node, btree, level)
    local node_data   = btree[node] or {}
    node_data.__level = level
    btree[node]       = node_data

    btree.trace:node_execute(btree, level, node)
    -- open callback
    if not node_data.is_open then
        if node.open then
            local ret = node:open(btree, node_data)
            if ret then
                btree.trace:node_status(node, ret)
                return ret
            end
        end
        node_data.is_open = true
    end

    -- run callback, get status
    local status = node:run(btree, node_data)
    btree.trace:node_status(btree, node, status)

    -- close callback
    if status == RUNNING then
        btree.open_nodes[node] = true
        return status
    else
        node_data.is_open = false
        if node.close then
            node:close(btree, node_data)
        end
        return status
    end
end

-- 根据权重决定子节点索引的顺序
function luabt.node_reorder(indexes, weight, total)
    for i = 1, #indexes do
        local rnd = mrandom(total)
        local acc = 0
        for j = i, #indexes do
            local w = weight[indexes[j]]
            acc     = acc + w
            if rnd <= acc then
                indexes[i], indexes[j] = indexes[j], indexes[i]
                total                  = total - w
                break
            end
        end
    end
end