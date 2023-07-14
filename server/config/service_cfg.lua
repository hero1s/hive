--service_cfg.lua
--luacheck: ignore 631

--导出配置内容
return {
    {
        id = 1, --[[ 服务id ]]
        name = 'hive', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = false, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = false, --[[ 安全退出 ]]
        pre_services = {}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 2, --[[ 服务id ]]
        name = 'router', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = false, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {"lobby"}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 3, --[[ 服务id ]]
        name = 'monitor', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = false, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {"router"}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 4, --[[ 服务id ]]
        name = 'robot', --[[ 服务名字 ]]
        mode = 3, --[[ 模式 ]]
        rely_router = false, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = false, --[[ 安全退出 ]]
        pre_services = {}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 5, --[[ 服务id ]]
        name = 'test', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = false, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = false, --[[ 安全退出 ]]
        pre_services = {}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 7, --[[ 服务id ]]
        name = 'dbsvr', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {"lobby"}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 8, --[[ 服务id ]]
        name = 'admin', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {"router"}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 9, --[[ 服务id ]]
        name = 'cachesvr', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 1, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {"lobby"}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 10, --[[ 服务id ]]
        name = 'online', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {"router"}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 11, --[[ 服务id ]]
        name = 'dbtool', --[[ 服务名字 ]]
        mode = 3, --[[ 模式 ]]
        rely_router = false, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = false, --[[ 安全退出 ]]
        pre_services = {}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 12, --[[ 服务id ]]
        name = 'tool', --[[ 服务名字 ]]
        mode = 3, --[[ 模式 ]]
        rely_router = false, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = false, --[[ 安全退出 ]]
        pre_services = {}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 101, --[[ 服务id ]]
        name = 'lobby', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = true, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 102, --[[ 服务id ]]
        name = 'match', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {"lobby"}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 104, --[[ 服务id ]]
        name = 'team', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {"lobby"}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 106, --[[ 服务id ]]
        name = 'center', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {"router"}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 107, --[[ 服务id ]]
        name = 'dsagent', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = true, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {"lobby"}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 108, --[[ 服务id ]]
        name = 'dscenter', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {"dsagent"}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 109, --[[ 服务id ]]
        name = 'login', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {"lobby"}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 201, --[[ 服务id ]]
        name = 'dirsvr', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = true, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 202, --[[ 服务id ]]
        name = 'web', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 203, --[[ 服务id ]]
        name = 'rank', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {"lobby"}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 204, --[[ 服务id ]]
        name = 'idip', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {"lobby"}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 205, --[[ 服务id ]]
        name = 'tlog_client', --[[ 服务名字 ]]
        mode = 3, --[[ 模式 ]]
        rely_router = false, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 206, --[[ 服务id ]]
        name = 'ai', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 207, --[[ 服务id ]]
        name = 'tencent_sdk', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {"lobby"}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 208, --[[ 服务id ]]
        name = 'cdkey', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 209, --[[ 服务id ]]
        name = 'pay', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = false, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {}, --[[ 安全退出前置服务 ]]
    },
    {
        id = 210, --[[ 服务id ]]
        name = 'login_key', --[[ 服务名字 ]]
        mode = 1, --[[ 模式 ]]
        rely_router = true, --[[ 依赖路由 ]]
        hash = 0, --[[ 服务固定hash ]]
        sole_ip = true, --[[ 校验ip ]]
        safe_stop = true, --[[ 安全退出 ]]
        pre_services = {}, --[[ 安全退出前置服务 ]]
    },
}
