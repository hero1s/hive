--devops_mgr.lua
local log_err    = logger.err
local sformat    = string.format
local update_mgr = hive.get("update_mgr")
local env_get    = environ.get
local DevopsMgr  = singleton()
function DevopsMgr:__init()
    self:setup()
end

--初始化
function DevopsMgr:setup()
    self:file_pid_oper(true)
    -- 退出通知
    update_mgr:attach_quit(self)
end

function DevopsMgr:on_quit()
    self:file_pid_oper(false)
end

--写入pid文件
function DevopsMgr:file_pid_oper(is_create)
    if hive.platform == "windows" then
        return
    end
    local lstdfs   = require("lstdfs")
    local filename = sformat("./pid/%s_%s.txt", env_get("HIVE_SERVICE"),hive.index)
    if is_create then
        local is_dir = lstdfs.is_directory("./pid")
        if is_dir ~= true then
            lstdfs.mkdir("./pid")
            log_err("pid dir is not exist,create")
        end
        local file = io.open(filename, "w")
        if not file then
            log_err(sformat("open pid file %s failed!", filename))
            return
        end
        file:write(hive.pid)
        file:close()
    else
        log_err(sformat("remove pid file %s ", filename))
        lstdfs.remove(filename)
    end
end

hive.devops_mgr = DevopsMgr()

return DevopsMgr
