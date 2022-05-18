--constant.lua

--核心基础错误(1-1000)
local KernCode = enum("KernCode", 0)
KernCode.SUCCESS            = 0     --成功
KernCode.NETWORK_ERROR      = 1     --网络错误
KernCode.PARAM_ERROR        = 2     --业务参数错误
KernCode.RPC_FAILED         = 3     --RPC调用失败
KernCode.OPERATOR_SELF      = 4     --不能对自己操作
KernCode.PLAYER_NOT_EXIST   = 5     --不能对自己操作
KernCode.TOKEN_ERROR        = 6     --登录token错误
KernCode.RPC_UNREACHABLE    = 7     --RPC目标不可达
KernCode.DB_NOTINIT         = 100   --数据库没有初始化
KernCode.LOGIC_FAILED       = 101   --业务执行失败
KernCode.MYSQL_FAILED       = 102   --MYSQL执行失败
KernCode.MONGO_FAILED       = 103   --MONGO执行失败
KernCode.REDIS_FAILED       = 104   --REDIS执行失败

--协议投flag掩码
local FlagMask              = enum("FlagMask", 0)
FlagMask.REQ                = 0x01  -- 请求
FlagMask.RES                = 0x02  -- 响应
FlagMask.ENCRYPT            = 0x04  -- 开启加密
FlagMask.ZIP                = 0x08  -- 开启zip压缩

--网络时间常量定义
local NetwkTime             = enum("NetwkTime", 0)
NetwkTime.CONNECT_TIMEOUT   = 3000      --连接等待时间
NetwkTime.RPC_CALL_TIMEOUT  = 5000      --RPC调用超时时间
NetwkTime.HTTP_CALL_TIMEOUT = 5000      --HTTP调用超时时间
NetwkTime.DB_CALL_TIMEOUT   = 5000      --DB调用超时时间
NetwkTime.ROUTER_TIMEOUT    = 10000     --router连接超时时间
NetwkTime.NETWORK_TIMEOUT   = 35000     --其他网络连接超时时间
NetwkTime.RECONNECT_TIME    = 5         --RPC连接重连时间（s）
NetwkTime.HEARTBEAT_TIME    = 2000      --RPC连接心跳时间

--常用时间周期
local PeriodTime = enum("PeriodTime", 0)
PeriodTime.FRAME_MS         = 100       --0.1秒（ms）
PeriodTime.HALF_MS          = 500       --0.5秒（ms）
PeriodTime.SECOND_MS        = 1000      --1秒（ms）
PeriodTime.SECOND_2_MS      = 2000      --2秒（ms）
PeriodTime.SECOND_3_MS      = 3000      --3秒（ms）
PeriodTime.SECOND_5_MS      = 5000      --5秒（ms）
PeriodTime.SECOND_10_MS     = 10000     --10秒（ms）
PeriodTime.SECOND_30_MS     = 30000     --30秒（ms）
PeriodTime.MINUTE_MS        = 60000     --60秒（ms）
PeriodTime.MINUTE_5_MS      = 300000    --5分钟（ms）
PeriodTime.MINUTE_10_MS     = 600000    --10分钟（ms）
PeriodTime.MINUTE_30_MS     = 1800000   --30分钟（ms）
PeriodTime.HOUR_MS          = 3600000   --1小时（ms）
PeriodTime.SECOND_5_S       = 5         --5秒（s）
PeriodTime.SECOND_10_S      = 10        --10秒（s）
PeriodTime.SECOND_30_S      = 30        --30秒（s）
PeriodTime.MINUTE_S         = 60        --60秒（s）
PeriodTime.MINUTE_5_S       = 300       --5分钟（s）
PeriodTime.MINUTE_10_S      = 600       --10分钟（s）
PeriodTime.MINUTE_30_S      = 1800      --30分钟（s）
PeriodTime.HOUR_S           = 3600      --1小时（s）
PeriodTime.DAY_S            = 86400     --1天（s）
PeriodTime.WEEK_S           = 604800    --1周（s）
PeriodTime.HOUR_M           = 60        --1小时（m

--数据加载状态
local DBLoading             = enum("DBLoading", 0)
DBLoading.INIT              = 0
DBLoading.LOADING           = 1
DBLoading.SUCCESS           = 2

-- GM命令类型
local GMType                = enum("GMType", 0)
GMType.GLOBAL               = 0       -- 全局相关
GMType.PLAYER               = 1       -- 玩家相关,ID为玩家的ID
GMType.SERVICE              = 2       -- 服务相关,ID按hash分发
GMType.SYSTEM               = 3       -- 业务相关,ID为队伍ID,房间ID等

--Cache错误码
local CacheType = enum("CacheType", 0)
CacheType.READ              = 1     -- 读
CacheType.WRITE             = 2     -- 写
CacheType.BOTH              = 3     -- 读写


--Cache错误码
local CacheCode = enum("CacheCode", 0)
CacheCode.CACHE_NOT_SUPPERT         = 10001  -- 不支持的缓存类型
CacheCode.CACHE_IS_NOT_EXIST        = 10002  -- 缓存不存在
CacheCode.CACHE_IS_HOLDING          = 10003  -- 缓存正在处理
CacheCode.CACHE_KEY_IS_NOT_EXIST    = 10004  -- key不存在
CacheCode.CACHE_FLUSH_FAILED        = 10005  -- flush失败
CacheCode.CACHE_KEY_LOCK_FAILD      = 10006  -- 用户锁失败
CacheCode.CACHE_DELETE_SAVE_FAILD   = 10007  -- 缓存删除失败