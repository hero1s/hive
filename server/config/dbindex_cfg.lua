--dbindex_cfg.lua
--luacheck: ignore 631

--导出配置内容
return {
    {
        id = 1, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'account', --[[ 数据表 ]]
        keys = {"open_id"}, --[[ key ]]
        name = 'openid', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 2, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'account', --[[ 数据表 ]]
        keys = {"bind_steam_id"}, --[[ key ]]
        name = 'bind_steam_id', --[[ 索引名称 ]]
        unique = false, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 3, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'white_list', --[[ 数据表 ]]
        keys = {"open_id"}, --[[ key ]]
        name = 'open_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 4, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'account_limit', --[[ 数据表 ]]
        keys = {"open_id"}, --[[ key ]]
        name = 'open_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 5, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_achieve', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 6, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_attribute', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 7, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_bag', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 8, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_battlepass', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 9, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_buff', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 10, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_career', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 11, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'career_image', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 12, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_prepare', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 13, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_role_info', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 14, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_role_skin', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 15, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_setting', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 16, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_vcard', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 17, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_standings', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 18, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_lottery', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 19, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_mmr', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 20, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_map', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 21, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_mail', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 22, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_salon', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 23, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_salon_sms', --[[ 数据表 ]]
        keys = {"player_id","role_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 24, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_friend', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 25, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'global_mail', --[[ 数据表 ]]
        keys = {"uuid"}, --[[ key ]]
        name = 'uuid', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 26, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_image', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 27, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_image', --[[ 数据表 ]]
        keys = {"player.nick"}, --[[ key ]]
        name = 'nick', --[[ 索引名称 ]]
        unique = false, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 28, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_reddot', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 29, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_shop', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 30, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_guide', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 31, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_sdk', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 32, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_name', --[[ 数据表 ]]
        keys = {"name"}, --[[ key ]]
        name = 'name', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 33, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_name', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = false, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 34, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'player_activity', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 35, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'recharge_order', --[[ 数据表 ]]
        keys = {"player_id"}, --[[ key ]]
        name = 'player_id', --[[ 索引名称 ]]
        unique = false, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 36, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'recharge_order', --[[ 数据表 ]]
        keys = {"order_id"}, --[[ key ]]
        name = 'order_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 37, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'recharge_order', --[[ 数据表 ]]
        keys = {"pay_order_id"}, --[[ key ]]
        name = 'pay_order_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 38, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'recharge_order', --[[ 数据表 ]]
        keys = {"insert_time"}, --[[ key ]]
        name = 'insert_time', --[[ 索引名称 ]]
        unique = false, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 39, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'standings', --[[ 数据表 ]]
        keys = {"room_id"}, --[[ key ]]
        name = 'room_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 40, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'standings', --[[ 数据表 ]]
        keys = {"ttl"}, --[[ key ]]
        name = 'ttl', --[[ 索引名称 ]]
        unique = false, --[[ 唯一 ]]
        expireAfterSeconds = 7776000, --[[ 过期时间(s) ]]
    },
    {
        id = 41, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'standings_tipoff', --[[ 数据表 ]]
        keys = {"room_id"}, --[[ key ]]
        name = 'room_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 42, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'standings_tipoff', --[[ 数据表 ]]
        keys = {"ttl"}, --[[ key ]]
        name = 'ttl', --[[ 索引名称 ]]
        unique = false, --[[ 唯一 ]]
        expireAfterSeconds = 7776000, --[[ 过期时间(s) ]]
    },
    {
        id = 43, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'stars_rank', --[[ 数据表 ]]
        keys = {"rank_id"}, --[[ key ]]
        name = 'rank_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 44, --[[ id ]]
        db_name = 'klbq', --[[ 数据库 ]]
        table_name = 'sta_activity', --[[ 数据表 ]]
        keys = {"open_id"}, --[[ key ]]
        name = 'open_id', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
    {
        id = 45, --[[ id ]]
        db_name = 'common', --[[ 数据库 ]]
        table_name = 'ai_data', --[[ 数据表 ]]
        keys = {"rank"}, --[[ key ]]
        name = 'rank', --[[ 索引名称 ]]
        unique = true, --[[ 唯一 ]]
        expireAfterSeconds = 0, --[[ 过期时间(s) ]]
    },
}
