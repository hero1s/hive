--dbcache_cfg.lua
--luacheck: ignore 631

--导出配置内容
return {
    {
        cache_name = 'standings', --[[ 缓存对象名称 ]]
        cache_table = 'standings', --[[ 缓存表名 ]]
        cache_key = 'room_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 300, --[[ 过期时间(秒) ]]
        store_time = 5, --[[ 强制存储时间(秒) ]]
        store_count = 2, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_image', --[[ 缓存对象名称 ]]
        cache_table = 'player_image', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_career', --[[ 缓存对象名称 ]]
        cache_table = 'player_career', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_role_info', --[[ 缓存对象名称 ]]
        cache_table = 'player_role_info', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_role_skin', --[[ 缓存对象名称 ]]
        cache_table = 'player_role_skin', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_setting', --[[ 缓存对象名称 ]]
        cache_table = 'player_setting', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_bag', --[[ 缓存对象名称 ]]
        cache_table = 'player_bag', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_attribute', --[[ 缓存对象名称 ]]
        cache_table = 'player_attribute', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_reward', --[[ 缓存对象名称 ]]
        cache_table = 'player_reward', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_vcard', --[[ 缓存对象名称 ]]
        cache_table = 'player_vcard', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_prepare', --[[ 缓存对象名称 ]]
        cache_table = 'player_prepare', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_buff', --[[ 缓存对象名称 ]]
        cache_table = 'player_buff', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_achieve', --[[ 缓存对象名称 ]]
        cache_table = 'player_achieve', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_battlepass', --[[ 缓存对象名称 ]]
        cache_table = 'player_battlepass', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_task', --[[ 缓存对象名称 ]]
        cache_table = 'player_task', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_friend', --[[ 缓存对象名称 ]]
        cache_table = 'player_friend', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_reddot', --[[ 缓存对象名称 ]]
        cache_table = 'player_reddot', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_mail', --[[ 缓存对象名称 ]]
        cache_table = 'player_mail', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_shop', --[[ 缓存对象名称 ]]
        cache_table = 'player_shop', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_salon', --[[ 缓存对象名称 ]]
        cache_table = 'player_salon', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_map', --[[ 缓存对象名称 ]]
        cache_table = 'player_map', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_mmr', --[[ 缓存对象名称 ]]
        cache_table = 'player_mmr', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_lottery', --[[ 缓存对象名称 ]]
        cache_table = 'player_lottery', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_activity', --[[ 缓存对象名称 ]]
        cache_table = 'player_activity', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_guide', --[[ 缓存对象名称 ]]
        cache_table = 'player_guide', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
    {
        cache_name = 'player_sdk', --[[ 缓存对象名称 ]]
        cache_table = 'player_sdk', --[[ 缓存表名 ]]
        cache_key = 'player_id', --[[ 缓存主键 ]]
        cache_db = 'default', --[[ 数据库 ]]
        expire_time = 1800, --[[ 过期时间(秒) ]]
        store_time = 20, --[[ 强制存储时间(秒) ]]
        store_count = 10, --[[ 强制存储更新次数 ]]
    },
}
