local lcodec     = require("lcodec")
local log_info   = logger.info

local thread_mgr = hive.get("thread_mgr")

--guid
thread_mgr:fork(function()
    ----------------------------------------------------------------
    for i = 1, 10 do
        local guid = lcodec.guid_new(104, 1, 5)
        log_info("test guid:%s:%s,serial:%s", i, guid,lcodec.guid_serial(guid))
        --log_info("test guid code:%s:%s", i, lcodec.guid_encode())
    end

    local guid = lcodec.guid_new(7, 54, 7)
    log_info("newguid: %s", guid)
    local group  = lcodec.guid_group(guid)
    local index  = lcodec.guid_index(guid)
    local gtype  = lcodec.guid_type(guid)
    local time   = lcodec.guid_time(guid)
    local serail = lcodec.guid_serial(guid)
    log_info("ssource-> group: %s, index: %s,gtype:%s, time:%s,serail:%s", group, index, gtype, datetime_ext.time_str(time), serail)

    thread_mgr:sleep(2000)
    guid = lcodec.guid_new(5, 34, 8)
    log_info("newguid: %s", guid)
    local group2, index2, gtype2, time2, serail = lcodec.guid_source(guid)
    log_info("nsource-> group: %s, index: %s,gtype:%s, time:%s,%s", group2, index2, gtype2, datetime_ext.time_str(time2), serail)

    logger.debug("-------test code---------")

    local guid      = lcodec.guid_new(2, 3, 4)
    local guid_code = lcodec.guid_encode(guid)
    local guid_num  = lcodec.guid_decode(guid_code)
    log_info("guid=%s --> %s -- > %s", guid, guid_code, guid_num)
    local name     = "tencent"
    local name_num = lcodec.guid_decode(name)
    log_info("guid:%s -->%s --> %s ", name, name_num, lcodec.guid_encode(name_num))

    log_info("jumphash value: %s,%s,%s", lcodec.jumphash("", 3), lcodec.jumphash(-1, 3), lcodec.jumphash(0, 3))
    local jumphash   = lcodec.jumphash
    --测试jumphash均衡性
    local count_jump = { 0, 0, 0, 0, 0, 0 }
    for i = 1, 100 do
        local value     = "toney" .. i
        local pos       = jumphash(value, #count_jump)
        count_jump[pos] = count_jump[pos] + 1
    end
    logger.debug("jump hash:%s", count_jump)

end)