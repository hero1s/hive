--database_cfg.lua
--luacheck: ignore 631

--导出配置内容
return {
    {
        driver = 'mongo', --[[ 类型 ]]
        db = 'klbq', --[[ 数据库名 ]]
        default = true, --[[ 默认数据库 ]]
        host = '10.100.0.48', --[[ ip地址 ]]
        port = 27019, --[[ 端口 ]]
    },
    {
        driver = 'mongo', --[[ 类型 ]]
        db = 'klbq_rmsg', --[[ 数据库名 ]]
        default = false, --[[ 默认数据库 ]]
        host = '10.100.0.48', --[[ ip地址 ]]
        port = 27019, --[[ 端口 ]]
    },
    {
        driver = 'redis', --[[ 类型 ]]
        db = 'redis', --[[ 数据库名 ]]
        default = true, --[[ 默认数据库 ]]
        host = '10.100.0.48', --[[ ip地址 ]]
        port = 6378, --[[ 端口 ]]
    },
    {
        driver = 'mysql', --[[ 类型 ]]
        db = 'klbq', --[[ 数据库名 ]]
        default = true, --[[ 默认数据库 ]]
        host = '10.100.0.48', --[[ ip地址 ]]
        user = 'root', --[[ 账号 ]]
        passwd = '123456', --[[ 密码 ]]
        port = 3306, --[[ 端口 ]]
    },
}
