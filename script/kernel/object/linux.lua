--linux.lua
--统计linux系统 cpu使用率，内存使用情况
local iopen       = io.open
local tonumber    = tonumber
local ssub        = string.sub
local sformat     = string.format
local ssplit      = string_ext.split

local LinuxStatis = singleton()
function LinuxStatis:__init()
end

function LinuxStatis:setup()
    self.pid         = hive.pid
    self.cpu_core    = self:calc_cpu_core()
    self.cpu_time    = self:calc_cpu_time()
    self.thread_time = self:calc_thread_time()
end

--计算cpu核心数量
function LinuxStatis:calc_cpu_core()
    local cpu_core  = 0
    local fp<close> = iopen("/proc/stat", "r")
    while true do
        local line = fp:read()
        if ssub(line, 1, 3) ~= "cpu" then
            --去掉第一行的汇总
            cpu_core = cpu_core - 1
            break
        end
        cpu_core = cpu_core + 1
    end
    return cpu_core
end

--计算cpu时间
function LinuxStatis:calc_cpu_time()
    local fstat<close> = iopen("/proc/stat", "r")
    local line         = fstat:read()
    local times        = ssplit(line, " ")
    local time         = 0
    if #times >= 11 then
        for i = 2, 11 do
            time = time + tonumber(times[i])
        end
    end
    return time
end

--计算主线程时间
function LinuxStatis:calc_thread_time()
    local fstat<close> = iopen(sformat("/proc/%d/stat", self.pid), "r")
    local line         = fstat:read()
    local times        = ssplit(line, " ")
    local time         = 0
    if #times >= 17 then
        for i = 14, 17 do
            time = time + tonumber(times[i])
        end
    end
    return time
end

--计算主线程cpu占用, 返回值为百分比，如50%返回50
function LinuxStatis:calc_cpu_rate()
    local cpu_time    = self:calc_cpu_time()
    local thread_time = self:calc_thread_time()
    local cpu_rate    = (thread_time - self.thread_time) / (cpu_time - self.cpu_time) * self.cpu_core * 100
    self.thread_time  = thread_time
    self.cpu_time     = cpu_time
    return cpu_rate
end

--计算主线程内存占用
function LinuxStatis:calc_memory()
    local linen, mem_res, mem_virt = 0, 0, 0
    local fstatus<close>           = iopen(sformat("/proc/%d/status", self.pid), "r")
    while linen < 22 do
        linen      = linen + 1
        local line = fstatus:read()
        if linen == 18 then
            local items = ssplit(line, " ")
            mem_virt    = tonumber(items[2])
        elseif linen == 22 then
            local items = ssplit(line, " ")
            mem_res     = tonumber(items[2])
        end
    end
    return mem_res, mem_virt
end

hive.linux_statis = LinuxStatis()

return LinuxStatis
