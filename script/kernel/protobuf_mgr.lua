--protobuf_mgr.lua
--升级pb库时,修改lpb_tointegerx函数支持浮点数自动转整数
local pairs        = pairs
local ipairs       = ipairs
local pcall        = pcall
local ldir         = stdfs.dir
local lappend      = stdfs.append
local lfilename    = stdfs.filename
local lextension   = stdfs.extension
local supper       = string.upper
local ssplit       = string_ext.split
local sends_with   = string_ext.ends_with
local tunpack      = table.unpack
local log_err      = logger.err
local log_warn     = logger.warn
local env_get      = environ.get
local setmetatable = setmetatable
local pb_decode    = protobuf.decode
local pb_encode    = protobuf.encode
local pb_enum_id   = protobuf.enum
local pb_bind_cmd  = protobuf.bind_cmd

local event_mgr    = hive.get("event_mgr")

local ProtobufMgr  = singleton()
local prop         = property(ProtobufMgr)
prop:accessor("pb_indexs", {})
prop:reader("pb_callbacks", {})
prop:accessor("allow_reload", false)

function ProtobufMgr:__init()
    self:load_protos()
    --设置加密串
    local xor_key = environ.number("HIVE_PROTO_XOR", 123456789)
    protobuf.xor_init(xor_key)
    --监听热更新
    event_mgr:add_trigger(self, "on_reload")
end

--加载pb文件
function ProtobufMgr:load_pbfiles(proto_dir, proto_file)
    local full_name = lappend(proto_dir, proto_file)
    --加载PB文件
    protobuf.loadfile(full_name)
    --设置枚举解析成number
    protobuf.option("enum_as_value")
    protobuf.option("encode_default_values")
    --注册枚举
    for name, basename, typ in protobuf.types() do
        if typ == "enum" then
            self:define_enum(name)
        end
    end
    --注册CMDID和PB的映射
    for name, basename, typ in protobuf.types() do
        if typ == "message" then
            self:define_command(name, basename)
        end
    end
end

--加载pb文件
function ProtobufMgr:load_protos()
    local proto_paths = ssplit(env_get("HIVE_PROTO_PATH", ""), ";")
    for _, proto_path in pairs(proto_paths) do
        local dir_files = ldir(proto_path)
        if not next(dir_files) then
            log_err("[ProtobufMgr][load_protos] {} not exist pb file", proto_path)
        end
        for _, file in pairs(dir_files) do
            if lextension(file.name) == ".pb" then
                local filename = lfilename(file.name)
                self:load_pbfiles(proto_path, filename)
            end
        end
    end
    self.allow_reload = true
end

function ProtobufMgr:verify_cmd(cmd_id)
    return self.pb_indexs[cmd_id] ~= nil
end

function ProtobufMgr:encode_byname(pb_name, data)
    local ok, pb_str = pcall(pb_encode, pb_name, data or {})
    if ok then
        return pb_str
    end
    log_err("[ProtobufMgr][encode_byname] name:{},data:{},res:{}", pb_name, data, pb_str)
end

function ProtobufMgr:encode(cmd_id, data)
    local proto_name = self.pb_indexs[cmd_id]
    if not proto_name then
        log_err("[ProtobufMgr][encode] find proto name failed! cmd_id:{}", cmd_id)
        return
    end
    local ok, pb_str = pcall(pb_encode, proto_name, data or {})
    if ok then
        return pb_str
    end
    log_err("[ProtobufMgr][encode] cmd_id:{},name:{},data:{},res:{}", cmd_id, proto_name, data, pb_str)
end

function ProtobufMgr:decode_byname(pb_name, pb_str)
    local ok, pb_data = pcall(pb_decode, pb_name, pb_str)
    if ok then
        return pb_data
    end
    log_err("[ProtobufMgr][decode_byname] name:{},data:{},res:{}", pb_name, pb_str, pb_data)
end

function ProtobufMgr:decode(cmd_id, pb_str)
    local proto_name = self.pb_indexs[cmd_id]
    if not proto_name then
        if type(cmd_id) ~= "string" then
            log_err("[ProtobufMgr][decode] find proto name failed! cmd_id:{}", cmd_id)
            return
        end
        proto_name = cmd_id
    end
    local ok, pb_data = pcall(pb_decode, proto_name, pb_str)
    if ok then
        return pb_data, proto_name
    end
    log_err("[ProtobufMgr][decode] cmd_id:{},res:{}", cmd_id, pb_data)
end

local function pbenum(full_name)
    return function(_, enum_name)
        local enum_val = pb_enum_id(full_name, enum_name)
        if not enum_val then
            log_err("[ProtobufMgr][pbenum] no enum {}.{}", full_name, enum_name)
        end
        return enum_val
    end
end

function ProtobufMgr:define_enum(full_name)
    local pb_enum = _G
    local nodes   = ssplit(full_name, ".")
    for _, name in ipairs(nodes) do
        if not pb_enum[name] then
            pb_enum[name] = {}
        end
        pb_enum = pb_enum[name]
    end
    setmetatable(pb_enum, { __index = pbenum(full_name) })
end

function ProtobufMgr:define_command(full_name, proto_name)
    local package_name = tunpack(ssplit(full_name, "."))
    local enum_set     = _G[package_name]
    if not enum_set then
        return
    end
    local proto_isreq = sends_with(proto_name, "_req")
    if proto_isreq or sends_with(proto_name, "_res") or sends_with(proto_name, "_ntf") then
        local msg_name = "NID_" .. supper(proto_name)
        for enum_type, enum in pairs(enum_set) do
            local msg_id = pb_enum_id(package_name .. "." .. enum_type, msg_name)
            if msg_id then
                self.pb_indexs[msg_id] = full_name
                pb_bind_cmd(msg_id, full_name)
                if proto_isreq then
                    local msg_res_name = msg_name:sub(0, -2) .. "S"
                    local msg_res_id   = pb_enum_id(package_name .. "." .. enum_type, msg_res_name)
                    if msg_res_id then
                        self.pb_callbacks[msg_id] = msg_res_id
                    end
                end
                return
            end
        end
        log_err("[ProtobufMgr][define_command] proto_name: [{}] can't find msg enum:[{}] !", proto_name, msg_name)
    end
end

function ProtobufMgr:register(doer, cmd_id, callback)
    local proto_name = self.pb_indexs[cmd_id]
    if not proto_name then
        log_err("[ProtobufMgr][register] proto_name: [{}] can't find!", cmd_id)
        return
    end
    event_mgr:add_cmd_listener(doer, cmd_id, callback)
end

-- 重新加载
function ProtobufMgr:on_reload()
    if not self.allow_reload then
        return
    end
    log_warn("[ProtobufMgr][on_reload]")
    -- gc env_
    protobuf.clear()
    -- register pb文件
    self:load_protos()
end

--返回回调id
function ProtobufMgr:callback_id(cmd_id)
    local pb_cbid = self.pb_callbacks[cmd_id]
    if not pb_cbid then
        log_warn("[ProtobufMgr][callback_id] cmdid [{}] find callback_id is nil", cmd_id)
    end
    return pb_cbid
end

-- 获取消息名称
function ProtobufMgr:msg_name(cmd_id)
    return self.pb_indexs[cmd_id]
end

hive.protobuf_mgr = ProtobufMgr()

return ProtobufMgr
