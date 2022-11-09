local lcodec   = require("lcodec")
local log_info = logger.info
--guid
----------------------------------------------------------------
local guid     = lcodec.guid_new(5, 512)
local sguid    = lcodec.guid_tostring(guid)
log_info("newguid-> guid: %s, n2s: %s", guid, sguid)
local nguid  = lcodec.guid_number(sguid)
local s2guid = lcodec.guid_tostring(nguid)
log_info("convert-> guid: %s, n2s: %s", nguid, s2guid)
local nsguid = lcodec.guid_string(5, 512)
log_info("newguid: %s", nsguid)
local group = lcodec.guid_group(nsguid)
local index = lcodec.guid_index(guid)
local time  = lcodec.guid_time(guid)
log_info("ssource-> group: %s, index: %s, time:%s", group, index, time)
local group2, index2, time2 = lcodec.guid_source(guid)
log_info("nsource-> group: %s, index: %s, time:%s", group2, index2, time2)

local guid      = lcodec.guid_new()
local guid_code = lcodec.guid_encode(guid)
local guid_num  = lcodec.guid_decode(guid_code)
log_info("guid=%s --> %s -- > %s", guid, guid_code, guid_num)
local name     = "tencent"
local name_num = lcodec.guid_decode(name)
log_info("guid:%s -->%s --> %s ", name, name_num, lcodec.guid_encode(name_num))

log_info("jumphash value: %s,%s,%s", lcodec.jumphash("", 3),lcodec.jumphash(-1, 3),lcodec.jumphash(0, 3))
