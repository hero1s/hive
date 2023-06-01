--signal.lua
local log_info    = logger.info
local get_signal  = hive.get_signal
local set_signal  = hive.set_signal
local pairs       = pairs

--信号定义
local SYS_SIGNAL  = {
    SIGHUP    = 1,
    SIGINT    = 2,
    SIGQUIT   = 3,
    SIGILL    = 4,
    SIGTRAP   = 5,
    SIGABRT   = 6,
    SIGIOT    = 6,
    SIGBUS    = 7,
    SIGFPE    = 8,
    SIGKILL   = 9,
    SIGUSR1   = 10,
    SIGSEGV   = 11,
    SIGUSR2   = 12,
    SIGPIPE   = 13,
    SIGALRM   = 14,
    SIGTERM   = 15,
    SIGSTKFLT = 16,
    SIGCHLD   = 17,
    SIGCONT   = 18,
    SIGSTOP   = 19,
    SIGTSTP   = 20,
    SIGTTIN   = 21,
    SIGTTOU   = 22,
    SIGURG    = 23,
    SIGXCPU   = 24,
    SIGXFSZ   = 25,
    SIGVTALRM = 26,
    SIGPROF   = 27,
    SIGWINCH  = 28,
    SIGIO     = 29,
    SIGPOLL   = 29,
    SIGPWR    = 30,
    SIGSYS    = 31,
    SIGUNUSED = 31,
    SIGRTMIN  = 32,
}

local EXIT_SIGNAL = {
    [SYS_SIGNAL.SIGINT]  = "SIGINT",
    [SYS_SIGNAL.SIGTERM] = "SIGTERM",
    [SYS_SIGNAL.SIGQUIT] = "SIGQUIT",
    [SYS_SIGNAL.SIGKILL] = "SIGKILL",
    [SYS_SIGNAL.SIGUSR1] = "SIGUSR1",
}

local SIG_HOTFIX  = SYS_SIGNAL.SIGUSR2

signal            = {}
signal.init       = function()
    for sig in pairs(EXIT_SIGNAL) do
        hive.register_signal(sig)
    end
    hive.register_signal(SIG_HOTFIX)
    hive.ignore_signal(SYS_SIGNAL.SIGPIPE)
    hive.default_signal(SYS_SIGNAL.SIGCHLD)
end

signal.clean      = function(signal)
    return set_signal(signal, false)
end

signal.set        = function(signal)
    return set_signal(signal, true)
end

signal.get        = function()
    return get_signal()
end

signal.check      = function(signalv)
    signalv = signalv or get_signal()
    for sig, sig_name in pairs(EXIT_SIGNAL) do
        if signalv & (1 << sig) ~= 0 then
            log_info("[signal][check] ->signal: %d, name:%s", sig, sig_name)
            return true
        end
    end
    return false
end

signal.reload     = function(signalv)
    signalv       = signalv or get_signal()
    local breload = (signalv & (1 << SIG_HOTFIX) ~= 0)
    if breload then
        set_signal(SIG_HOTFIX, false)
    end
    return breload
end

signal.quit       = function()
    set_signal(SYS_SIGNAL.SIGQUIT, true)
end

signal.hotfix     = function()
    set_signal(SIG_HOTFIX, true)
end
