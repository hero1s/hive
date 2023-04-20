--数据库连接字符串列表, 分割符为";"
--单个连接串格式: driver://[username:password@]host1[:port1][,host2[:port2],...[,hostN[:portN]]][/[database][?options]]
--options格式: key1=value1&key2=value2
return {
    {
        name    = 'klbq', --[[ 别名 ]]
        default = true, --[[ 默认数据库 ]]
        url     = [[mongodb://_:_@10.100.0.48:27019/klbq?readPreference=secondaryPreferred]]
    },
    {
        name    = 'rmsg', --[[ 别名 ]]
        url     = [[mongodb://_:_@10.100.0.48:27019/klbq_rmsg?readPreference=secondaryPreferred]]
    },
    {
        name    = 'activity', --[[ 别名 ]]
        url     = [[mongodb://_:_@10.100.0.48:27019/klbq_activity?readPreference=secondaryPreferred]]
    },
    {
        name    = 'redis', --[[ 别名 ]]
        default = true, --[[ 默认数据库 ]]
        url     = [[redis://_:_@10.100.0.48:6378]]
    },
    {
        name    = 'test_mysql', --[[ 别名 ]]
        default = true, --[[ 默认数据库 ]]
        url     = [[mysql://root:123456@10.100.0.48:3306/klbq]]
    },
}
