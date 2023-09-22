--devops_mgr.lua
local log_err    = logger.err
local log_info   = logger.info
local sformat    = string.format
local update_mgr = hive.get("update_mgr")
local env_get    = environ.get
local readfile   = io_ext.readfile
local DevopsMgr  = singleton()
function DevopsMgr:__init()
    self:setup()
end

--初始化
function DevopsMgr:setup()
    self:file_pid_oper(true)
    self:attach_service()
    -- 退出通知
    update_mgr:attach_quit(self)
end

function DevopsMgr:on_quit()
    self:file_pid_oper(false)
end

--挂载附加服务
function DevopsMgr:attach_service()
    local service = env_get("HIVE_ATTACH_SERVICE")
    if service and #service > 3 then
        import(service)
    end
end

--pid文件名
function DevopsMgr:pid_file_name()
    local no_index = environ.status("HIVE_PID_NOINDEX")
    if no_index then
        return sformat("./pid/%s.txt", env_get("HIVE_SERVICE"))
    else
        return sformat("./pid/%s_%s.txt", env_get("HIVE_SERVICE"), hive.index)
    end
end

--写入pid文件
function DevopsMgr:file_pid_oper(is_create)
    if not hive.is_linux() then
        return
    end
    local filename = self:pid_file_name()
    if is_create then
        local is_dir = stdfs.is_directory("./pid")
        if is_dir ~= true then
            stdfs.mkdir("./pid")
            log_err("pid dir is not exist,create")
        end
        local file = io.open(filename, "w")
        if not file then
            log_err("[DevopsMgr][file_pid_oper]open pid file {} failed!", filename)
            return
        end
        file:write(hive.pid)
        file:close()
        log_info("[DevopsMgr][file_pid_oper] pid:{}", hive.pid)
    else
        log_info("remove pid file {} ", filename)
        local pid = readfile(filename)
        if pid then
            pid = tonumber(pid)
        end
        if pid == hive.pid then
            stdfs.remove(filename)
        end
    end
end

hive.devops_mgr = DevopsMgr()

return DevopsMgr
