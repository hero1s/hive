--数据库连接字符串列表, 分割符为";"
--单个连接串格式: driver://[username:password@]host1[:port1][,host2[:port2],...[,hostN[:portN]]][/[database][?options]]
--options格式: key1=value1&key2=value2
return {
    {
        name    = 'klbq', --[[ 别名 ]]
        default = true, --[[ 默认数据库 ]]
        max_ops = 50000, --[[ 队列大小 ]]
        url     = [[mongodb://_:_@10.100.0.48:27019/klbq?readPreference=secondaryPreferred]]
    },
    {
        name    = 'rmsg', --[[ 别名 ]]
        max_ops = 50000, --[[ 队列大小 ]]
        url     = [[mongodb://_:_@10.100.0.48:27019/klbq_rmsg?readPreference=secondaryPreferred]]
    },
    {
        name    = 'common', --[[ 别名 ]]
        max_ops = 50000, --[[ 队列大小 ]]
        url     = [[mongodb://_:_@10.100.0.48:27019/klbq_common?readPreference=secondaryPreferred]]
    },
    {
        name    = 'redis', --[[ 别名 ]]
        default = true, --[[ 默认数据库 ]]
        url     = [[redis://_:_@10.100.0.48:6378]]
    }
}
