--etcd.lua
import("network/http_client.lua")

local sformat       = string.format
local json_encode   = hive.json_encode

local http          = hive.get("http_client")

local CLIENT_KEYS   = '/v2/keys'
local CLIENT_ENDPOINTS = {
    version         = '/version',
    stats_self      = '/v2/stats/self',
    stats_store     = '/v2/stats/store',
    stats_leader    = '/v2/stats/leader',
}

local Etcd = class()
function Etcd:__init(etcd_url)
    self.etcd_url = etcd_url
end

function Etcd:_set(path, value, opts)
    opts = opts or {}
    local header = {
        prevExist = opts.prevExist,
        prevIndex = opts.prevIndex,
    }
    local body = { ttl = opts.ttl }
    if opts.dir then
        body.dir = opts.dir
    else
        body.value = (type(value) == "table") and json_encode(value) or value
    end
    local url = sformat("%s%s", self.etcd_url, CLIENT_ENDPOINTS[path] or CLIENT_KEYS .. path)
    local ok, status, res
    if opts.inOrder then
        ok, status, res = http:call_post(url, json_encode(body), header)
    else
        ok, status, res = http:call_put(url, json_encode(body), header)
    end
    if ok and (status == 200 or status == 201) then
        return true, res
    end
    return false, res
end

function Etcd:_get(path, opts)
    opts = opts or {}
    local query = {
        wait = opts.wait,
        waitIndex = opts.waitIndex,
        recursive = opts.recursive,
        consistent = opts.consistent,
    }
    local url = CLIENT_ENDPOINTS[path] or CLIENT_KEYS .. path
    local ok, status, res = http:call_get(url, query)
    if ok and status == 200 then
        return true, res
    end
    return false, res
end

function Etcd:_del(path, opts)
    --opts = opts or {}
    local url = sformat("%s%s", self.etcd_url, CLIENT_ENDPOINTS[path] or CLIENT_KEYS .. path)
    local ok, status, res = http:call_del(url)
    if ok and status == 200 then
        return true, res
    end
    return false, res
end

--version
function Etcd:version()
    return self:_get("version")
end

-- /stats
function Etcd:stats_leader()
    return self:_get("stats_leader")
end

function Etcd:stats_self()
    return self:_get("stats_self")
end

function Etcd:stats_store()
    return self:_get("stats_store")
end

-- set key-val and ttl
function Etcd:set(key, val, ttl)
    return self:_set(key, val, { ttl = ttl })
end

-- set key-val and ttl if key does not exists (atomic create)
function Etcd:setnx(key, val, ttl)
    return self:_set(key, val, { ttl = ttl, prevExist = false })
end

-- set key-val and ttl if key is exists (update)
function Etcd:setx(key, val, ttl, modifiedIndex)
    return self:_set(key, val, {
        ttl = ttl,
        prevExist = true,
        prevIndex = modifiedIndex
    })
end

-- in-order keys
function Etcd:push(key, val, ttl)
    return self:_set(key, val, {
        ttl = ttl,
        inOrder = true
    })
end

-- get key-val
function Etcd:get(key, consistent)
    return self:_get(key, { consistent = consistent })
end

-- delete key
-- atomic delete if val or modifiedIndex are not nil.
function Etcd:del(key, val, modifiedIndex)
    return self:_del(key, {
        prevValue = val,
        prevIndex = modifiedIndex
    })
end

-- wait
function Etcd:wait(key, modifiedIndex)
    return self:_get(key, {
        wait = true,
        waitIndex = modifiedIndex,
    })
end

-- dir
function Etcd:mkdir(key, ttl)
    return self:_set(key, nil, {
        ttl = ttl,
        dir = true
   })
end

-- mkdir if not exists
function Etcd:mkdirnx(key, ttl)
    return self:_set(key, nil, {
        ttl = ttl,
        dir = true,
        prevExist = false
    })
end

function Etcd:readdir(key, recursive, consistent)
    return self:_get(key, {
        dir = true,
        recursive = recursive,
        consistent = consistent
     })
end

function Etcd:rmdir(key, recursive)
    return self:_del(key, {
        dir = true,
        recursive = recursive
    })
end

-- wait with recursive
function Etcd:waitdir(key, modifiedIndex)
    return self:_get(key, {
        wait = true,
        recursive = true,
        waitIndex = modifiedIndex,
    })
end

-- set ttl for key
function Etcd:setTTL(key, ttl)
    -- get prev-value
    local old = self:get(key)
    if old then
        local header = {
            prevExist = true,
            prevValue = old.node.value,
            prevIndex = (not old.node.dir) and old.node.modifiedIndex or nil,
        }
        local body = {
            ttl = ttl >= 0 and ttl or '',
            dir = old.node.dir,
            value = old.node.value
        }
        local url = sformat("%s%s", self.etcd_url, key)
        local ok, status, res = http:call_put(url, json_encode(body), header)
        if ok and status == 200 then
            return true, res
        end
        return false, res
    end
    return false, 404
end

return Etcd
