local log_debug  = logger.debug

local thread_mgr = hive.get("thread_mgr")

function test_a(index)
    local _lock<close> = thread_mgr:lock("sync_lock_test")
    thread_mgr:sleep(10)
    log_debug("test_a:%s", index)
end

function test_b(index)
    local _lock<close> = thread_mgr:lock("sync_lock_test")
    thread_mgr:sleep(100)
    test_a(index)
    log_debug("test_b:%s", index)
end

function test_c(index)
    local _lock<close> = thread_mgr:lock("sync_lock_test")
    thread_mgr:sleep(1000)
    test_b(index)
    log_debug("test_c:%s", index)
end

function test_no_reentry(index)
    local _lock<close> = thread_mgr:lock("no_reentry",true)
    if not _lock then
        log_debug("function is runing")
        return
    end
    thread_mgr:sleep(500)
    test_b(index)
    log_debug("test_no_reentry:%s", index)
end

thread_mgr:fork(function()
    for i = 1, 10 do
        thread_mgr:fork(function()
            test_c(i)
        end)
    end

    thread_mgr:sleep(10000)

    for i = 1, 10 do
        thread_mgr:fork(function()
            test_c(i)
        end)
    end
    thread_mgr:fork(function()
        test_no_reentry(1)
    end)
    thread_mgr:fork(function()
        test_no_reentry(2)
    end)
end)






