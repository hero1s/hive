--cache_obj_cfg.lua
--luacheck: ignore 631

--导出配置内容
return {
    {
        cache_name = 'player', --[[ 缓存对象名称 ]]
        cache_db = 'klbq', --[[ 数据库 ]]
        expire_time = 600, --[[ 过期时间(秒) ]]
        flush_time = 86400, --[[ 强制过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 5, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_image', --[[ 缓存对象名称 ]]
        cache_db = 'klbq', --[[ 数据库 ]]
        expire_time = 3600, --[[ 过期时间(秒) ]]
        flush_time = 86400, --[[ 强制过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 2, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_name', --[[ 缓存对象名称 ]]
        cache_db = 'klbq', --[[ 数据库 ]]
        expire_time = 3600, --[[ 过期时间(秒) ]]
        flush_time = 3600, --[[ 强制过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 2, --[[ 强制存储更新次数 ]]
    },
}
