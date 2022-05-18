-- 数据库配置信息,全局配置,mongo,redis,cachesvr服务都需要读取
-- 数据库相关服务最好是分开独立机器部署,规划好后配置变更较小

return

{
    --数据库类型          数据库名              ip                   端口             用户名密码(无密码设置nil)
    { driver = "mongo", db = "klbq",        host = "10.100.0.48", port = "27018", user = nil, passwd = nil, default = true },--默认数据库
    { driver = "mongo", db = "klbq_rmsg",   host = "10.100.0.48", port = "27018", user = nil, passwd = nil },

    --redis
    { driver = "redis", db = "redis", host = "10.100.0.48", port = "6378", user = nil, passwd = nil, default = true },

}
