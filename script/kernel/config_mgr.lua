-- 配置管理器
local iopen       = io.open
local tpack       = table.pack
local tunpack     = table.unpack
local tsort       = table.sort
local sformat     = string.format
local tkvarray    = table_ext.kvarray
local log_err     = logger.err
local ConfigTable = import("feature/config_table.lua")

local ConfigMgr   = singleton()
function ConfigMgr:__init()
    -- 配置对象列表
    self.table_list      = {}
    -- 配置表加载方式
    self.table_load_info = {}
end

--- 配置热更新
function ConfigMgr:reload(notify)
    local reload_cfg_map = {}
    for name in pairs(self.table_list) do
        local load_info = self.table_load_info[name]
        if load_info then
            local load_func = load_info.func
            local params    = load_info.params
            local _, reload = ConfigMgr[load_func](self, tunpack(params))
            if reload then
                reload_cfg_map[name] = true
            end
        end
    end
    if notify then
        local event_mgr = hive.load("event_mgr")
        if event_mgr then
            local thread_mgr = hive.get("thread_mgr")
            thread_mgr:fork(function()
                event_mgr:notify_trigger("reload_config", reload_cfg_map)
            end)
        end
    end
end

function ConfigMgr:load_enum_table(name, ename, enum_key, main_key)
    local conf_tab, reload = self:load_table(name, main_key)
    if conf_tab then
        local enum_obj = enum(ename, 0)
        for _, conf in conf_tab:iterator() do
            enum_obj[conf[enum_key]] = conf[main_key]
        end
    end
    self.table_load_info[name] = {
        func   = "load_enum_table",
        params = tpack(name, ename, enum_key, main_key),
    }
    return conf_tab, reload
end

--加载配置表并生成枚举
function ConfigMgr:init_enum_table(name, ename, enum_key, main_key)
    local conf_tab = self.table_list[name]
    if not conf_tab then
        conf_tab = self:load_enum_table(name, ename, enum_key, main_key)
    end
    return conf_tab
end

function ConfigMgr:load_table(name, ...)
    local conf_tab = self.table_list[name]
    local reload   = true
    if conf_tab then
        reload = conf_tab:setup(name, ...)
    else
        conf_tab              = ConfigTable()
        self.table_list[name] = conf_tab
        conf_tab:setup(name, ...)
    end

    if not self.table_load_info[name] then
        self.table_load_info[name] = {
            func   = "load_table",
            params = tpack(name, ...),
        }
    end

    return conf_tab, reload
end

-- 初始化配置表
function ConfigMgr:init_table(name, ...)
    local conf_tab = self.table_list[name]
    if not conf_tab then
        conf_tab = self:load_table(name, ...)
    end
    return conf_tab
end

-- 获取配置表
function ConfigMgr:get_table(name)
    return self.table_list[name]
end

-- 关闭配置表
function ConfigMgr:close_table(name)
    self.table_list[name] = nil
end

-- 获取配置表一条记录
function ConfigMgr:find_one(name, ...)
    local conf_tab = self.table_list[name]
    if conf_tab then
        return conf_tab:find_one(...)
    end
end

-- 筛选配置表记录
function ConfigMgr:select(name, query)
    local conf_tab = self.table_list[name]
    if conf_tab then
        return conf_tab:select(query)
    end
end

-- 生成枚举lua文件
function ConfigMgr:gen_enum_file(name, ename, enum_key, main_key, desc)
    logger.debug("gen_enum_file:{},ename:{},enum_key:{},main_key:{},desc:{}", name, ename, enum_key, main_key, desc)
    local conf_tab    = self:load_table(name, main_key)
    local gen_objs    = {}
    local max_key_len = 20
    if conf_tab then
        for _, conf in conf_tab:iterator() do
            local rename = ename
            if conf[ename] then
                --存在配置列则用配置列名,否则以指定名为枚举名
                rename = conf[ename]
            end
            if string.len(rename) > 1 then
                if not gen_objs[rename] then
                    gen_objs[rename] = {}
                end
                local key_len = string.len(conf[enum_key])
                if key_len > 1 then
                    table.insert(gen_objs[rename], { conf[enum_key], conf[main_key], conf[desc] })
                    if key_len > max_key_len then
                        max_key_len = key_len
                    end
                end
            end
        end
    end
    local out_f    = sformat("../server/constant/enum_%s.lua", name)
    local out_file = iopen(out_f, "w")
    if not out_file then
        log_err("[ConfigMgr][gen_enum_file] open out file ({}) failed!", out_f)
        return
    end
    --移除空类型
    for k, v in pairs(gen_objs) do
        if #v == 0 then
            gen_objs[k] = nil
        end
    end
    gen_objs = tkvarray(gen_objs)
    tsort(gen_objs, function(a, b)
        return a[2][1][2] < b[2][1][2]
    end)
    local function cat_string(str, len, expr)
        str = tostring(str)
        if #str < len then
            for i = 1, len - #str do
                str = str .. expr
            end
        end
        return str
    end
    local buff = sformat("\n\n-----表格:%s 自动生成\n\n", name)
    local mf   = '%s.%s\t=\t%s  --%s\n'
    for _, obj in ipairs(gen_objs) do
        local en   = obj[1]
        local objs = obj[2]
        tsort(objs, function(a, b)
            return a[2] < b[2]
        end)
        buff = buff .. sformat("local %s    = enum(\"%s\",0)\n", en, en)
        for _, v in ipairs(objs) do
            buff = buff .. mf:format(en, cat_string(v[1], max_key_len, " "), cat_string(v[2], 6, " "), v[3])
        end
        buff = buff .. "\n\n"
    end
    out_file:write(buff)
    out_file:close()
end



-- export
hive.config_mgr = ConfigMgr()
return ConfigMgr
