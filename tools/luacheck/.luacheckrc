-- 单个全局变量 
self=false
-- 全局变量集合
stds.hive = {
    globals = {
        --common
        "tonubmer", "lfs", "util", "coroutine", "ncmd_cs", "ncmd_ds",
        "hive_const", "table_ext", "string_ext", "math_ext", "http_helper", "redis_key", "io_ext","datetime_ext", "mongo_key",
        "hive", "environ", "signal", "http", "guid_room", "guid_player","guid_item","luabt", "service", "logger", "utility",
        "import","import_dir", "class", "enum", "mixin", "property", "singleton", "super", "implemented","logfeature",
        "classof", "is_class", "is_subclass", "instanceof", "conv_class"
    }
}
std = "max+hive"
-- 排除文件
exclude_files = {
    "../../hive/tools/",
	"../../hive/server/qtest/",
	"../../tools/"
}
-- 圈复杂度
max_cyclomatic_complexity = 16
-- 最大代码长度
max_code_line_length = 180
-- 最大注释长度
max_comment_line_length = 160
-- 忽略警告
ignore = {
    "212", "213", "512",
    "21/_.*" --(W212)unused argument '_arg'
}

-- 更多配置参考 https://luacheck.readthedocs.io/en/stable/config.html