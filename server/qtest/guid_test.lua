
local lguid     = require("lguid")
local log_info      = logger.info
--guid
----------------------------------------------------------------
local guid = lguid.guid_new(5, 512)
local sguid = lguid.guid_tostring(guid)
log_info("newguid-> guid: %s, n2s: %s", guid, sguid)
local nguid = lguid.guid_number(sguid)
local s2guid = lguid.guid_tostring(nguid)
log_info("convert-> guid: %s, n2s: %s", nguid, s2guid)
local nsguid = lguid.guid_string(5, 512)
log_info("newguid: %s", nsguid)
local group = lguid.guid_group(nsguid)
local index = lguid.guid_index(guid)
local time = lguid.guid_time(guid)
log_info("ssource-> group: %s, index: %s, time:%s", group, index, time)
local group2, index2, time2 = lguid.guid_source(guid)
log_info("nsource-> group: %s, index: %s, time:%s", group2, index2, time2)

local guid      = lguid.guid_new()
local guid_code = lguid.encode_code(guid)
local guid_num  = lguid.decode_code(guid_code)
log_info("guid=%s --> %s -- > %s", guid, guid_code, guid_num)
local name = "tencent"
local name_num = lguid.decode_code(name)
log_info("guid:%s -->%s --> %s ",name,name_num,lguid.encode_code(name_num))
