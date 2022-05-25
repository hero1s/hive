--service_cfg.lua
--luacheck: ignore 631

--导出配置内容
return {
    {
        id = 1, --[[ 服务id ]]
        name = 'hive', --[[ 服务名字 ]]
        router = false, --[[ 是否启动路由 ]]
        monitor = false, --[[ 是否启动监控 ]]
        hash = 0, --[[ 服务固定hash ]]
    },
    {
        id = 2, --[[ 服务id ]]
        name = 'router', --[[ 服务名字 ]]
        router = false, --[[ 是否启动路由 ]]
        monitor = false, --[[ 是否启动监控 ]]
        hash = 0, --[[ 服务固定hash ]]
    },
    {
        id = 3, --[[ 服务id ]]
        name = 'monitor', --[[ 服务名字 ]]
        router = false, --[[ 是否启动路由 ]]
        monitor = false, --[[ 是否启动监控 ]]
        hash = 0, --[[ 服务固定hash ]]
    },
    {
        id = 4, --[[ 服务id ]]
        name = 'robot', --[[ 服务名字 ]]
        router = false, --[[ 是否启动路由 ]]
        monitor = false, --[[ 是否启动监控 ]]
        hash = 0, --[[ 服务固定hash ]]
    },
    {
        id = 5, --[[ 服务id ]]
        name = 'test', --[[ 服务名字 ]]
        router = true, --[[ 是否启动路由 ]]
        monitor = true, --[[ 是否启动监控 ]]
        hash = 0, --[[ 服务固定hash ]]
    },
    {
        id = 6, --[[ 服务id ]]
        name = 'proxy', --[[ 服务名字 ]]
        router = true, --[[ 是否启动路由 ]]
        monitor = true, --[[ 是否启动监控 ]]
        hash = 0, --[[ 服务固定hash ]]
    },
    {
        id = 7, --[[ 服务id ]]
        name = 'dbsvr', --[[ 服务名字 ]]
        router = true, --[[ 是否启动路由 ]]
        monitor = true, --[[ 是否启动监控 ]]
        hash = 0, --[[ 服务固定hash ]]
    },
    {
        id = 8, --[[ 服务id ]]
        name = 'admin', --[[ 服务名字 ]]
        router = true, --[[ 是否启动路由 ]]
        monitor = true, --[[ 是否启动监控 ]]
        hash = 0, --[[ 服务固定hash ]]
    },
    {
        id = 9, --[[ 服务id ]]
        name = 'dirsvr', --[[ 服务名字 ]]
        router = true, --[[ 是否启动路由 ]]
        monitor = true, --[[ 是否启动监控 ]]
        hash = 0, --[[ 服务固定hash ]]
    },
    {
        id = 10, --[[ 服务id ]]
        name = 'lobby', --[[ 服务名字 ]]
        router = true, --[[ 是否启动路由 ]]
        monitor = true, --[[ 是否启动监控 ]]
        hash = 0, --[[ 服务固定hash ]]
    },
    {
        id = 11, --[[ 服务id ]]
        name = 'match', --[[ 服务名字 ]]
        router = true, --[[ 是否启动路由 ]]
        monitor = true, --[[ 是否启动监控 ]]
        hash = 0, --[[ 服务固定hash ]]
    },
    {
        id = 12, --[[ 服务id ]]
        name = 'room', --[[ 服务名字 ]]
        router = true, --[[ 是否启动路由 ]]
        monitor = true, --[[ 是否启动监控 ]]
        hash = 0, --[[ 服务固定hash ]]
    },
    {
        id = 13, --[[ 服务id ]]
        name = 'team', --[[ 服务名字 ]]
        router = true, --[[ 是否启动路由 ]]
        monitor = true, --[[ 是否启动监控 ]]
        hash = 0, --[[ 服务固定hash ]]
    },
    {
        id = 14, --[[ 服务id ]]
        name = 'center', --[[ 服务名字 ]]
        router = true, --[[ 是否启动路由 ]]
        monitor = true, --[[ 是否启动监控 ]]
        hash = 0, --[[ 服务固定hash ]]
    },
    {
        id = 15, --[[ 服务id ]]
        name = 'chat', --[[ 服务名字 ]]
        router = true, --[[ 是否启动路由 ]]
        monitor = true, --[[ 是否启动监控 ]]
        hash = 0, --[[ 服务固定hash ]]
    },
    {
        id = 50, --[[ 服务id ]]
        name = 'tencent_sdk', --[[ 服务名字 ]]
        router = true, --[[ 是否启动路由 ]]
        monitor = true, --[[ 是否启动监控 ]]
        hash = 1, --[[ 服务固定hash ]]
    },
    {
        id = 51, --[[ 服务id ]]
        name = 'cachesvr', --[[ 服务名字 ]]
        router = true, --[[ 是否启动路由 ]]
        monitor = true, --[[ 是否启动监控 ]]
        hash = 2, --[[ 服务固定hash ]]
    },
    {
        id = 52, --[[ 服务id ]]
        name = 'online', --[[ 服务名字 ]]
        router = true, --[[ 是否启动路由 ]]
        monitor = true, --[[ 是否启动监控 ]]
        hash = 2, --[[ 服务固定hash ]]
    },
}
