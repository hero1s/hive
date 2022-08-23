--mysql.lua
local lcrypt                     = require("lcrypt")
local Socket                     = import("driver/socket.lua")
local QueueFIFO                  = import("container/queue_fifo.lua")

local tonumber                   = tonumber
local lsha1                      = lcrypt.sha1
local ssub                       = string.sub
local srep                       = string.rep
local sgsub                      = string.gsub
local sbyte                      = string.byte
local schar                      = string.char
local spack                      = string.pack

local log_err                    = logger.err
local log_info                   = logger.info
local sformat                    = string.format
local sunpack                    = string.unpack
local tpack                      = table.pack
local tunpack                    = table.unpack
local tointeger                  = math.tointeger

local thread_mgr                 = hive.get("thread_mgr")
local update_mgr                 = hive.get("update_mgr")

local DB_TIMEOUT                 = hive.enum("NetwkTime", "DB_CALL_TIMEOUT")

--charset编码
local CHARSET_MAP                = {
    _default = 0,
    big5     = 1,
    dec8     = 3,
    cp850    = 4,
    hp8      = 6,
    koi8r    = 7,
    latin1   = 8,
    latin2   = 9,
    swe7     = 10,
    ascii    = 11,
    ujis     = 12,
    sjis     = 13,
    hebrew   = 16,
    tis620   = 18,
    euckr    = 19,
    koi8u    = 22,
    gb2312   = 24,
    greek    = 25,
    cp1250   = 26,
    gbk      = 28,
    latin5   = 30,
    armscii8 = 32,
    utf8     = 33,
    ucs2     = 35,
    cp866    = 36,
    keybcs2  = 37,
    macce    = 38,
    macroman = 39,
    cp852    = 40,
    latin7   = 41,
    utf8mb4  = 45,
    cp1251   = 51,
    utf16    = 54,
    utf16le  = 56,
    cp1256   = 57,
    cp1257   = 59,
    utf32    = 60,
    binary   = 63,
    geostd8  = 92,
    cp932    = 95,
    eucjpms  = 97,
    gb18030  = 248
}

-- constants
local COM_QUERY                  = "\x03"
local COM_PING                   = "\x0e"
local COM_STMT_PREPARE           = "\x16"
local COM_STMT_EXECUTE           = "\x17"
local COM_STMT_CLOSE             = "\x19"
local COM_STMT_RESET             = "\x1a"

local CURSOR_TYPE_NO_CURSOR      = 0x00
local SERVER_MORE_RESULTS_EXISTS = 8

-- mysql field value type converters
local converters                 = {
    [0x01] = tonumber, -- tiny
    [0x02] = tonumber, -- short
    [0x03] = tonumber, -- long
    [0x04] = tonumber, -- float
    [0x05] = tonumber, -- double
    [0x08] = tonumber, -- long long
    [0x09] = tonumber, -- int24
    [0x0d] = tonumber, -- year
    [0xf6] = tonumber, -- newdecimal
}

local function _get_int1(data, pos, signed)
    return sunpack(signed and "<i1" or "<I1", data, pos)
end

local function _get_int2(data, pos, signed)
    return sunpack(signed and "<i2" or "<I2", data, pos)
end

local function _get_int3(data, pos, signed)
    return sunpack(signed and "<i3" or "<I3", data, pos)
end

local function _get_int4(data, pos, signed)
    return sunpack(signed and "<i4" or "<I4", data, pos)
end

local function _get_int8(data, pos, signed)
    return sunpack(signed and "<i8" or "<I8", data, pos)
end

local function _get_float(data, pos)
    return sunpack("<f", data, pos)
end

local function _get_double(data, pos)
    return sunpack("<d", data, pos)
end

local function _from_length_coded_bin(data, pos)
    local first = sbyte(data, pos)
    if not first then
        return nil, pos
    end
    if first >= 0 and first <= 250 then
        return first, pos + 1
    end
    if first == 251 then
        return nil, pos + 1
    end
    if first == 252 then
        return sunpack("<I2", data, pos + 1)
    end
    if first == 253 then
        return sunpack("<I3", data, pos + 1)
    end
    if first == 254 then
        return sunpack("<I8", data, pos + 1)
    end
    return false, pos + 1
end

local function _set_length_coded_bin(n)
    if n < 251 then
        return schar(n)
    end
    if n < (1 << 16) then
        return spack("<BI2", 0xfc, n)
    end
    if n < (1 << 24) then
        return spack("<BI3", 0xfd, n)
    end
    return spack("<BI8", 0xfe, n)
end

local function _get_datetime(data, pos)
    local len, year, month, day, hour, minute, second
    local value
    len, pos = _from_length_coded_bin(data, pos)
    if len == 7 then
        year, month, day, hour, minute, second, pos = string.unpack("<I2BBBBB", data, pos)
        value                                       = sformat("%04d-%02d-%02d %02d:%02d:%02d", year, month, day, hour, minute, second)
    else
        value = "2017-09-09 20:08:09"
        pos   = pos + len
    end
    return value, pos
end

local function _from_cstring(data, pos)
    return sunpack("z", data, pos)
end

local function _from_length_coded_str(data, pos)
    local len, npos = _from_length_coded_bin(data, pos)
    if len == nil then
        return nil, npos
    end
    return ssub(data, npos, npos + len - 1), npos + len
end

--字段类型参考
--https://dev.mysql.com/doc/dev/mysql-server/8.0.12/binary__log__types_8h.html
--enum_field_types 枚举类型定义
local _binary_parser = {
    [0x01] = _get_int1,
    [0x02] = _get_int2,
    [0x03] = _get_int4,
    [0x04] = _get_float,
    [0x05] = _get_double,
    [0x07] = _get_datetime,
    [0x08] = _get_int8,
    [0x09] = _get_int3,
    [0x0c] = _get_datetime,
    [0x0f] = _from_length_coded_str,
    [0x10] = _from_length_coded_str,
    [0xf9] = _from_length_coded_str,
    [0xfa] = _from_length_coded_str,
    [0xfb] = _from_length_coded_str,
    [0xfc] = _from_length_coded_str,
    [0xfd] = _from_length_coded_str,
    [0xfe] = _from_length_coded_str
}

--参数字段类型转换
local store_types    = {
    ["number"]  = function(v)
        if not tointeger(v) then
            return spack("<I2", 0x05), spack("<d", v)
        else
            return spack("<I2", 0x08), spack("<i8", v)
        end
    end,
    ["string"]  = function(v)
        return spack("<I2", 0x0f), _set_length_coded_bin(#v) .. v
    end,
    --bool转换为0,1
    ["boolean"] = function(v)
        if v then
            return spack("<I2", 0x01), schar(1)
        else
            return spack("<I2", 0x01), schar(0)
        end
    end,
    ["nil"]     = function(v)
        return spack("<I2", 0x06), ""
    end
}

local function _async_call(context, quote, callback, ...)
    local session_id = thread_mgr:build_session_id()
    if not context.commit_id then
        context.commit_id = session_id
    end
    context.args       = { ... }
    context.callback   = callback
    context.session_id = session_id
    return thread_mgr:yield(session_id, quote, DB_TIMEOUT)
end

local function _compute_token(password, scramble)
    if password == "" then
        return ""
    end
    local nscramble = ssub(scramble, 1, 20)
    local stage1    = lsha1(password)
    local stage2    = lsha1(stage1)
    local stage3    = lsha1(nscramble .. stage2)
    local i         = 0
    return sgsub(stage3, ".", function(x)
        i = i + 1
        return schar(sbyte(x) ~ sbyte(stage1, i))
    end)
end

local function _compose_stmt_execute(self, stmt, cursor_type, args)
    local arg_num = #args
    if arg_num ~= stmt.param_count then
        return false, sformat("require stmt.param_count %d get arg_num %d[no:30902]", stmt.param_count, arg_num)
    end
    local cmd_packet = spack("<c1I4BI4", COM_STMT_EXECUTE, stmt.prepare_id, cursor_type, 0x01)
    if arg_num > 0 then
        local types_buf, values_buf   = "", ""
        local field_index, null_count = 1, (arg_num + 7) // 8
        for i = 1, null_count do
            local byte = 0
            for j = 0, 7 do
                if field_index < arg_num then
                    local bit = args[field_index] and 0 or 1
                    byte      = byte | (bit << j)
                end
                field_index = field_index + 1
            end
            cmd_packet = cmd_packet .. schar(byte)
        end
        for i, v in ipairs(args) do
            local f = store_types[type(v)]
            if not f then
                return false, sformat("invalid parameter %s, type:%s", v, type(v))
            end
            local ts, vs = f(v)
            types_buf    = types_buf .. ts
            values_buf   = values_buf .. vs
        end
        cmd_packet = cmd_packet .. schar(0x01) .. types_buf .. values_buf
    end
    return self:_compose_packet(cmd_packet)
end

--ok报文
local function _parse_ok_packet(packet)
    --1 byte 0x00报文标志(不处理)
    --1-9 byte 受影响行数
    local affrows, pos_aff  = _from_length_coded_bin(packet, 2)
    --1-9 byte 索引ID值
    local index, pos_idx    = _from_length_coded_bin(packet, pos_aff)
    --2 byte 服务器状态
    local status, pos_state = sunpack("<I2", packet, pos_idx)
    --2 byte 警告数量编号
    local warncnt, pos_warn = sunpack("<I2", packet, pos_state)
    --n byte 服务器消息
    local msg               = ssub(packet, pos_warn + 1)
    local res               = { affected_rows = affrows, insert_id = index, server_status = status, warning_count = warncnt, message = msg }
    if status & SERVER_MORE_RESULTS_EXISTS ~= 0 then
        return res, "again"
    end
    return res
end

--eof报文
local function _parse_eof_packet(packet)
    --1 byte 0xfe报文标志(不处理)
    --2 byte 警告数量编号
    local warning_count, pos = sunpack("<I2", packet, 2)
    --2 byte 状态标志位
    local status_flags       = sunpack("<I2", packet, pos)
    return warning_count, status_flags
end

--error报文
local function _parse_err_packet(packet)
    --1 byte 0xff报文标志(不处理)
    --2 byte 错误编号
    local errno, pos = sunpack("<I2", packet, 2)
    --1 byte 服务器状态标识，恒为#(不处理)
    --5 byte 服务器状态
    local sqlstate   = ssub(packet, pos + 1, pos + 6 - 1)
    local message    = ssub(packet, pos + 6)
    return sformat("errno:%d, msg:%s,sqlstate:%s", errno, message, sqlstate)
end

--field 报文结构
local function _parse_field_packet(packet)
    --n byte 目录名称
    local _, pos_catlog    = _from_length_coded_str(packet, 1)
    --n byte 数据库名称
    local _, pos_db        = _from_length_coded_str(packet, pos_catlog)
    --n byte 数据表名称
    local _, pos_table     = _from_length_coded_str(packet, pos_db)
    --n byte 数据表原始名称
    local _, pos_ori_table = _from_length_coded_str(packet, pos_table)
    --n byte 列（字段）名称
    local name, pos_col    = _from_length_coded_str(packet, pos_ori_table)
    --n byte 列（字段）原始名称
    local _, pos_ori_col   = _from_length_coded_str(packet, pos_col)
    --1 byte 填充值(不处理)
    --2 byte 字符编码(不处理)
    --4 byte 列（字段）长度(不处理)
    local pos_col_type     = pos_ori_col + 7
    --1 byte 列（字段）类型
    local type             = sbyte(packet, pos_col_type)
    local pos_col_flags    = pos_col_type + 1
    --2 byte 列（字段）标志
    local flags            = sunpack("<I2", packet, pos_col_flags)
    -- https://mariadb.com/kb/en/resultset/
    local signed           = (flags & 0x20 == 0) and true or false
    return { type = type, signed = signed, name = name }
end

--row_data报文
local function _parse_row_data_packet(packet, fields)
    local pos, row = 1, {}
    for _, field in ipairs(fields) do
        local value
        value, pos = _from_length_coded_str(packet, pos)
        if not field.ignore then
            if value ~= nil then
                local conv = converters[field.type]
                if conv then
                    value = conv(value)
                end
            end
            row[field.name] = value
        end
    end
    return row
end

--row_data报文（二进制）
local function _parse_row_data_binary(packet, fields)
    -- 空位图, 前两个bit系统保留 (列数量 + 7 + 2) / 8
    local pos                         = 2 + (#fields + 9) // 8
    local field_idx, null_fields, row = 1, {}, {}
    --空字段表
    for i = 2, pos - 1 do
        for j = 0, 7 do
            if field_idx > 2 then
                null_fields[field_idx - 2] = (sbyte(packet, i) & (1 << j) ~= 0)
            end
            field_idx = field_idx + 1
        end
    end
    for i, field in ipairs(fields) do
        if not null_fields[i] then
            local value
            local parser = _binary_parser[field.typ]
            value, pos   = parser(packet, pos, field.signed)
            if not field.ignore then
                row[field.name] = value
            end
        end
    end
    return row
end

local function _parse_not_data_packet(packet, typ)
    if typ == "ERR" then
        return nil, _parse_err_packet(packet)
    end
    if typ == "OK" then
        return _parse_ok_packet(packet)
    end
    return nil, "packet type " .. typ .. " not supported"
end

local function _parae_packet_type(buff)
    if not buff or #buff == 0 then
        return nil, "empty packet"
    end
    local typ         = "DATA"
    local field_count = sbyte(buff, 1)
    if field_count == 0x00 then
        typ = "OK"
    elseif field_count == 0xff then
        typ = "ERR"
    elseif field_count == 0xfe then
        typ = "EOF"
    end
    return typ
end

local function _recv_field_resp(context, packet, typ)
    if typ == "EOF" then
        return true
    end
    if typ == "DATA" then
        return true, _parse_field_packet(packet)
    end
    return _parse_not_data_packet(packet, typ)
end

local function _recv_rows_resp(context, packet, typ, fields, binary)
    if typ == "EOF" then
        local _, status_flags = _parse_eof_packet(packet)
        if status_flags & SERVER_MORE_RESULTS_EXISTS ~= 0 then
            return true, "again"
        end
        return true
    end
    if typ == "DATA" then
        if binary then
            return true, _parse_row_data_binary(packet, fields)
        end
        return true, _parse_row_data_packet(packet, fields)
    end
    return _parse_not_data_packet(packet, typ)
end

--result_set报文
local function _parse_result_set_packet(context, packet, ignores, binary)
    --Result Set Header
    --1-9 byte Field结构计数field_count
    local _, pos_field = _from_length_coded_bin(packet, 1)
    --1-9 byte 额外信息
    local _            = _from_length_coded_bin(packet, pos_field)
    -- Field结构
    local fields       = {}
    while true do
        local ok, field = _async_call(context, "recv field packet", _recv_field_resp)
        if not ok then
            return nil, field
        end
        if not field then
            break
        end
        field.ignore        = ignores and ignores[field.name]
        fields[#fields + 1] = field
    end
    -- Row Data
    local rows = {}
    while true do
        local rok, row = _async_call(context, "recv row packet", _recv_rows_resp, fields, binary)
        if not rok then
            return nil, row
        end
        if not row then
            break
        end
        if row == "again" then
            return rows, row
        end
        rows[#rows + 1] = row
    end
    return rows
end

local function _recv_result_set_resp(context, packet, typ, ignores, binary)
    if typ == "DATA" then
        local rows, rerr = _parse_result_set_packet(context, packet, ignores, binary)
        if not rows then
            return nil, rerr
        end
        return rows, rerr
    end
    return _parse_not_data_packet(packet, typ)
end

local function _recv_query_resp(context, packet, typ, ignores, binary)
    local res, err = _recv_result_set_resp(context, packet, typ, ignores, binary)
    if not res then
        return false, err
    end
    if err ~= "again" then
        return true, res
    end
    local multiresultset = { res }
    while err == "again" do
        res, err = _async_call(context, "recv resultset packet", _recv_result_set_resp, ignores, binary)
        if not res then
            return false, err
        end
        multiresultset[#multiresultset + 1] = res
    end
    multiresultset.multiresultset = true
    return true, multiresultset
end

local function _compute_auth_token(plugin, passwd, scramble)
    if plugin == "mysql_native_password" then
        return true, _compute_token(passwd, scramble), true
    end
    return false, "only mysql_native_password is supported"
end

local function _recv_auth_resp(context, packet, typ, passwd)
    if typ == "ERR" then
        return false, _parse_err_packet(packet)
    end
    if typ == "EOF" then
        if #packet == 1 then
            return false, "old pre-4.1 authentication protocol not supported"
        end
        local plugin, pos = _from_cstring(packet, 2)
        if not plugin then
            return false, "malformed packet"
        end
        local scramble = ssub(packet, pos);
        return _compute_auth_token(plugin, passwd, scramble)
    end
    return true, packet
end

local function _recv_prepare_resp(context, packet, typ)
    if typ == "ERR" then
        return false, _parse_err_packet(packet)
    end
    --第一节只能是OK
    if typ ~= "OK" then
        return false, sformat("first typ must be OK, now %s[no:300201]", typ)
    end
    local prepare_id, field_count, param_count, warning_count = sunpack("<I4I2I2xI2", packet, 2)
    local params, fields                                      = {}, {}
    if param_count > 0 then
        while true do
            local ok, field = _async_call(context, "recv field packet", _recv_field_resp)
            if not ok then
                return false, field
            end
            if not field then
                break
            end
            params[#params + 1] = field
        end
    end
    if field_count > 0 then
        while true do
            local ok, field = _async_call(context, "recv field packet", _recv_field_resp)
            if not ok then
                return false, field
            end
            if not field then
                break
            end
            fields[#fields + 1] = field
        end
    end
    return true, { params      = params, fields = fields, prepare_id = prepare_id,
                   field_count = field_count, param_count = param_count, warning_count = warning_count
    }
end

local MysqlDB = class()
local prop    = property(MysqlDB)
prop:reader("ip", nil)          --mysql地址
prop:reader("sock", nil)        --网络连接对象
prop:reader("name", "")         --dbname
prop:reader("port", 3306)       --mysql端口
prop:reader("user", nil)        --user
prop:reader("passwd", nil)      --passwd
prop:reader("packet_no", 0)     --passwd
prop:reader("sessions", nil)                --sessions
prop:accessor("charset", "_default")        --charset
prop:accessor("max_packet_size", 1024 * 1024) --max_packet_size,1mb

function MysqlDB:__init(conf)
    self.ip       = conf.host
    self.db       = conf.db
    self.port     = conf.port
    self.user     = conf.user
    self.passwd   = conf.passwd
    self.sessions = QueueFIFO()
    self.sock     = Socket(self)
    --update
    update_mgr:attach_minute(self)
    update_mgr:attach_second(self)
end

function MysqlDB:__release()
    self:close()
end

function MysqlDB:close()
    if self.sock then
        self.sessions:clear()
        self.sock:close()
    end
end

function MysqlDB:on_minute()
    if self.sock:is_alive() and not self:ping() then
        self:close()
    end
end

function MysqlDB:on_second()
    if not self.sock:is_alive() then
        if not self.sock:connect(self.ip, self.port) then
            log_err("[MysqlDB][on_second] connect db(%s:%s:%s) failed!", self.ip, self.port, self.db)
            return
        end
        local ok, err, ver = self:auth()
        if not ok then
            log_err("[MysqlDB][on_second] auth db(%s:%d:%s) failed! because: %s", self.ip, self.port, self.db, err)
            return
        end
        log_info("[MysqlDB][on_second] connect db(%s:%d-%s[%s]) success!", self.ip, self.port, self.db, ver)
    end
end

function MysqlDB:auth()
    if not self.passwd or not self.user or not self.db then
        return false, "user or password or dbname not config!"
    end
    local context = { cmd = "auth" }
    self.sessions:push(context)
    local ok, packet = _async_call(context, "recv auth packet", _recv_auth_resp)
    if not ok then
        return false, packet
    end
    --1 byte 协议版本号 (服务器认证报文开始)(skip)
    --n byte 服务器版本号
    local version, pos = _from_cstring(packet, 2)
    if not version then
        return false, "bad handshake initialization packet: bad server version"
    end
    --4 byte thread_id (skip)
    pos             = pos + 4
    --8 byte 挑战随机数1
    local scramble1 = ssub(packet, pos, pos + 8 - 1)
    if not scramble1 then
        return false, "1st part of scramble not found"
    end
    --1 byte 填充值 (skip)
    --2 byte server_capabilities (skip)
    --1 byte server_lang (skip)
    --2 byte server_status (skip)
    --2 byte server_capabilities high (skip)
    --1 byte 挑战长度 (未使用) (skip)
    --10 byte 填充值 (skip)
    pos             = pos + 8 + 1 + 2 + 1 + 2 + 2 + 1 + 10
    --12 byte 挑战随机数2
    local scramble2 = ssub(packet, pos, pos + 12 - 1)
    if not scramble2 then
        return false, "2nd part of scramble not found"
    end
    --1 byte 挑战数结束(服务器认证报文结束)(skip)
    --n byte plugin
    local plugin = "mysql_native_password"
    if #packet > pos + 12 then
        plugin = _from_cstring(packet, pos + 13)
    end
    --客户端认证报文
    --2 byte 客户端权能标志
    --2 byte 客户端权能标志扩展
    local client_flags = 260047
    --4 byte 最大消息长度
    local packet_size  = self.max_packet_size
    --1 byte 字符编码
    local charset      = schar(CHARSET_MAP[self.charset])
    --23 byte 填充值
    local fuller       = srep("\0", 23)
    --n byte 用户名
    --n byte 挑战认证数据（scramble1+scramble2+passwd）
    local scramble     = scramble1 .. scramble2
    local tok, token   = _compute_auth_token(plugin, self.passwd, scramble)
    if not tok then
        return false, token
    end
    --n byte 数据库名（可选）
    local req                    = spack("<I4I4c1c23zs1z", client_flags, packet_size, charset, fuller, self.user, token, self.db)
    local authpacket             = self:_compose_packet(req)
    local aok, nscramble, double = self:request(authpacket, _recv_auth_resp, "mysql_auth", self.passwd)
    if double then
        --double sha1 auth
        aok, nscramble = self:request(self:_compose_packet(nscramble), _recv_auth_resp, "mysql_auth_double")
    end
    return aok, nscramble, version
end

function MysqlDB:on_socket_error(sock, token, err)
    log_err("[MysqlDB][on_socket_error] mysql server lost")
    for _, context in self.sessions:iter() do
        thread_mgr:response(context.session_id, false, err)
    end
    self.sessions:clear()
end

function MysqlDB:on_socket_recv(sock, token)
    while true do
        --mysql 响应报文结构
        local hdata = sock:peek(4)
        if not hdata then
            break
        end
        --3 byte消息长度
        local length, pos = sunpack("<I3", hdata, 1)
        --1 byte 消息序列号
        self.packet_no    = sbyte(hdata, pos)
        --n byte 消息内容
        local bdata       = nil
        if length > 0 then
            bdata = sock:peek(length, 4)
            if not bdata then
                break
            end
        end
        sock:pop(4 + length)
        --收到一个完整包
        local context = self.sessions:head()
        if context then
            thread_mgr:fork(function()
                local callback   = context.callback
                local session_id = context.session_id
                local typ, err   = _parae_packet_type(bdata)
                if not typ then
                    if session_id == context.commit_id then
                        self.sessions:pop()
                    end
                    thread_mgr:response(session_id, false, err)
                    return
                end
                local result = tpack(callback(context, bdata, typ, tunpack(context.args)))
                if session_id == context.commit_id then
                    self.sessions:pop()
                end
                thread_mgr:response(session_id, tunpack(result))
            end)
        end
    end
end

function MysqlDB:request(packet, callback, quote, param)
    if not self.sock:send(packet) then
        return false, "send request failed"
    end
    local context = { cmd = quote }
    self.sessions:push(context)
    return _async_call(context, quote, callback, param)
end

function MysqlDB:query(query, ignores)
    self.packet_no = -1
    log_info("[MysqlDB][query] sql: %s", query)
    local querypacket = self:_compose_packet(COM_QUERY .. query)
    return self:request(querypacket, _recv_query_resp, "mysql_query", ignores)
end

-- 注册预处理语句
function MysqlDB:prepare(sql)
    self.packet_no    = -1
    local querypacket = self:_compose_packet(COM_STMT_PREPARE .. sql)
    return self:request(querypacket, _recv_prepare_resp, "mysql_prepare")
end

--执行预处理语句
function MysqlDB:execute(stmt, ...)
    self.packet_no         = -1
    local querypacket, err = _compose_stmt_execute(self, stmt, CURSOR_TYPE_NO_CURSOR, { ... })
    if not querypacket then
        return false, sformat("%s[no:30902]", err)
    end
    return self:request(querypacket, _recv_query_resp, "mysql_execute")
end

--重置预处理句柄
function MysqlDB:stmt_reset(prepare_id)
    self.packet_no    = -1
    local cmd_packet  = spack("c1<I4", COM_STMT_RESET, prepare_id)
    local querypacket = self:_compose_packet(cmd_packet)
    return self:request(querypacket, _recv_query_resp, "mysql_stmt_reset")
end

--关闭预处理句柄
function MysqlDB:stmt_close(prepare_id)
    self.packet_no    = -1
    local cmd_packet  = spack("c1<I4", COM_STMT_CLOSE, prepare_id)
    local querypacket = self:_compose_packet(cmd_packet)
    return self:request(querypacket, _recv_query_resp, "mysql_stmt_close")
end

function MysqlDB:ping()
    self.packet_no    = -1
    local querypacket = self:_compose_packet(COM_PING)
    local ok, err     = self:request(querypacket, _recv_query_resp, "mysql_ping")
    if not ok then
        log_err("[MysqlDB][ping] mysql ping db(%s:%d-%s) failed: %s!", self.ip, self.port, self.db, err)
    end
    return ok
end

function MysqlDB:_compose_packet(req)
    --mysql 请求报文结构
    --3 byte 消息长度
    --1 byte 消息序列号，每次请求从0开始
    --n byte 消息内容
    local size     = #req
    self.packet_no = self.packet_no + 1
    return spack("<I3Bc" .. size, size, self.packet_no, req)
end

local escape_map = {
    ['\0']  = "\\0",
    ['\b']  = "\\b",
    ['\n']  = "\\n",
    ['\r']  = "\\r",
    ['\t']  = "\\t",
    ['\26'] = "\\Z",
    ['\\']  = "\\\\",
    ["'"]   = "\\'",
    ['"']   = '\\"',
}

function MysqlDB:escape_sql(str)
    return sformat("'%s'", sgsub(str, "[\0\b\n\r\t\26\\\'\"]", escape_map))
end

return MysqlDB
