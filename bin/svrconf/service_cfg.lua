-- 服务配置信息,全局配置,所有服务都需要读取
-- 服务配置运维只可以修改index,cachesvr的hash值,即服务数量

return

{
    { id = 1,  name = 'router',      router = false, hash = 0  },
    { id = 2,  name = 'tool',        router = false, hash = 0, },
    { id = 3,  name = 'monitor',     router = false, hash = 0, },
    { id = 4,  name = 'robot',       router = false, hash = 0, },
    { id = 5,  name = 'test',        router = false, hash = 0, },
    { id = 6,  name = 'mongo',       router = true,  hash = 0, },
    { id = 7,  name = 'proxy',       router = true,  hash = 0, },
    { id = 8,  name = 'dirsvr',      router = true,  hash = 0, },
    { id = 9,  name = 'lobby',       router = true,  hash = 0, },
    { id = 10, name = 'cachesvr',    router = true,  hash = 2, },
    { id = 11, name = 'match',       router = true,  hash = 0, },
    { id = 12, name = 'room',        router = true,  hash = 0, },
    { id = 13, name = 'team',        router = true,  hash = 0, },
    { id = 14, name = 'center',      router = true,  hash = 0, },
    { id = 15, name = 'index',       router = true,  hash = 2, },
    { id = 16, name = 'platform',    router = true,  hash = 0, },
    { id = 17, name = 'redis',       router = true,  hash = 0, },
	{ id = 18, name = 'tencent_sdk', router = true,  hash = 1, },
    { id = 19, name = 'admin',       router = true,  hash = 0, },
}