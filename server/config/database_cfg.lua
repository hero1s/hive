--database_cfg.lua
--luacheck: ignore 631

--导出配置内容
return {
    {
        driver = 'mongo', --[[ 类型 ]]
        name = 'klbq', --[[ 别名 ]]
        db = 'klbq', --[[ 数据库名 ]]
        default = true, --[[ 默认数据库 ]]
        host = '10.100.0.48', --[[ ip地址 ]]
        port = 27019, --[[ 端口 ]]
        user = '', --[[ 账号 ]]
        passwd = '', --[[ 密码 ]]
    },
    {
        driver = 'mongo', --[[ 类型 ]]
        name = 'rmsg', --[[ 别名 ]]
        db = 'klbq_rmsg', --[[ 数据库名 ]]
        default = false, --[[ 默认数据库 ]]
        host = '10.100.0.48', --[[ ip地址 ]]
        port = 27019, --[[ 端口 ]]
        user = '', --[[ 账号 ]]
        passwd = '', --[[ 密码 ]]
    },
    {
        driver = 'redis', --[[ 类型 ]]
        name = 'redis', --[[ 别名 ]]
        db = 'redis', --[[ 数据库名 ]]
        default = true, --[[ 默认数据库 ]]
        host = '10.100.0.48', --[[ ip地址 ]]
        port = 6378, --[[ 端口 ]]
        user = '', --[[ 账号 ]]
        passwd = '', --[[ 密码 ]]
    },
    {
        driver = 'mysql', --[[ 类型 ]]
        name = 'klbq', --[[ 别名 ]]
        db = 'klbq', --[[ 数据库名 ]]
        default = true, --[[ 默认数据库 ]]
        host = '10.100.0.48', --[[ ip地址 ]]
        port = 3306, --[[ 端口 ]]
        user = 'root', --[[ 账号 ]]
        passwd = '123456', --[[ 密码 ]]
    },
}
