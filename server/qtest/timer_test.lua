--log_test.lua
local ltimer    = require("ltimer")
local sformat   = string.format
local log_info  = logger.info

--log.init("./newlog/", "qtest", 500000)

local msec, sec = ltimer.time()
log_info("time: sec:{}, msec:{}", sec, msec)
--ltimer:sleep(2000)
local now = ltimer.now()
local now_ms = ltimer.now_ms()
log_info("time: now:{}, now_ms:{}", now, now_ms)

local clock = ltimer.clock()
local clock_ms = ltimer.clock_ms()
log_info("time: steady:{}, steady_ms:{}", clock, clock_ms)

local timer_mgr = hive.get("timer_mgr")
local thread_mgr = hive.get("thread_mgr")

thread_mgr:fork(function()
    log_info("once")
    timer_mgr:once(500, function(escape_ms)
        log_info("once: {}", escape_ms)
    end, 3)

    log_info("loop")
    timer_mgr:loop(1000, function(escape_ms)
        log_info("loop: {}", escape_ms)
    end)

    log_info("register")
    timer_mgr:register(500, 1000, 5, function(escape_ms)
        log_info("register: {}", escape_ms)
    end)

    logger.debug("once")
    timer_mgr:once(500, function(escape_ms)
        logger.debug(sformat("once: {}", escape_ms))
    end)

    logger.debug("loop")
    timer_mgr:loop(1000, function(escape_ms)
        logger.debug(sformat("loop: {}", escape_ms))
    end)

    logger.debug("register")
    timer_mgr:register(500, 1000, 5, function(escape_ms)
        logger.debug(sformat("register: {}", escape_ms))
    end)
    local cex            = "0 0 17 * * 1"
    local time, time_str = ltimer.cron_next(cex)
    logger.debug("the cron: [{}] -->next on time:[{}],[{}]", cex, time, time_str)

end)

--[[        //前6个字段分别表示：
        //       秒钟：0-59
        //       分钟：0-59
        //       小时：1-23
        //       日期：1-31
        //       月份：1-12
        //       星期：0-6（0 表示周日）

        //还可以用一些特殊符号：
        //       *： 表示任何时刻
//       ,：　表示分割，如第三段里：2,4，表示 2 点和 4 点执行
//　　    －：表示一个段，如第三端里： 1-5，就表示 1 到 5 点
//       /n : 表示每个n的单位执行一次，如第三段里，*/1, 就表示每隔 1 个小时执行一次命令。也可以写成1-23/1.
/////////////////////////////////////////////////////////
//  0/30 * * * * *                        每 30 秒 执行
//  0 43 21 * * *                         21:43 执行
//  0 15 05 * * * 　　                     05:15 执行
//  0 0 17 * * *                          17:00 执行
//  0 0 17 * * 1                          每周一的 17:00 执行
//  0 0,10 17 * * 0,2,3                   每周日,周二,周三的 17:00和 17:10 执行
//  0 0-10 17 1 * *                       毎月1日从 17:00 到 7:10 毎隔 1 分钟 执行
//  0 0 0 1,15 * 1                        毎月1日和 15 日和 一日的 0:00 执行
//  0 42 4 1 * * 　 　                     毎月1日的 4:42 分 执行
//  0 0 21 * * 1-6　　                     周一到周六 21:00 执行
//  0 0,10,20,30,40,50 * * * *　           每隔 10 分 执行
//  0 */10 * * * * 　　　　　　              每隔 10 分 执行
//  0 * 1 * * *　　　　　　　　               从 1:0 到 1:59 每隔 1 分钟 执行
//  0 0 1 * * *　　　　　　　　               1:00 执行
//  0 0 */1 * * *　　　　　　　               毎时 0 分 每隔 1 小时 执行
//  0 0 * * * *　　　　　　　　               毎时 0 分 每隔 1 小时 执行
//  0 2 8-20/3 * * *　　　　　　             8:02,11:02,14:02,17:02,20:02 执行
//  0 30 5 1,15 * *　　　　　　              1 日 和 15 日的 5:30 执行]]
--os.exit()
