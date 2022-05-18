--base.lua

luabt.BTConst   = {
    -- Node Status
    SUCCESS     = 1,
    FAIL        = 2,
    RUNNING     = 3,

    -- Parallel Policy
    SUCCESS_ONE = 1, -- success when one child success
    SUCCESS_ALL = 2, -- success when all children success
    FAIL_ONE    = 3, -- fail when one child fail
    FAIL_ALL    = 4, -- fail when all children fail
}

luabt.NODE_TYPE = {
    SUCCESS         = 1,
    FAILED          = 2,
    INVERT          = 3,
    RANDOM          = 4,
    PRIORITY        = 5,
    PARALLEL        = 6,    -- 并行节点
    CONDITION       = 7,    -- 条件装饰器
    SEQUENCE        = 8,    -- 顺序节点
    MEM_SEQUENCE    = 9,
    MEM_PRIORITY    = 10,
    WEIGHT_SEQUENCE = 11,
    WEIGHT_PRIORITY = 12,
}
