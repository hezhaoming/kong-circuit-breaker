local typedefs = require "kong.db.schema.typedefs"

local STATUS_CODE = {
    401,
    404,
    405,
    429
}



return {
    name = "circuit-breaker",
    fields = {
        { config = {
            type = "record",
            --type,required,unique,default,immutable,enum,regex
            fields = {
                { status = { type = "number", default = 429, one_of = STATUS_CODE }, },
                --降级回调接口
                { systemName = { type = "string", }, },
                --降级回调接口
                { api_call_back = { type = "string", }, },
                --接口超时时间，毫秒
                { api_request_timeout_ms = { type = "number", default = 6000 }, },
                -- 滑动窗口大小
                { metrics_rolling_size = { type = "number", default = 10 }, },
                -- 时间粒度
                { metrics_granularity = { type = "number", default = 5 }, },
                -- 请求出错比例
                { metrics_error_ratio = { type = "number", default = 45 }, },
                -- 熔断恢复期
                { min_recovery_time_ms = { type = "number", default = 1500 }, },
                -- 请求数量，请求量很小不care熔断
                { threshold_request_count = { type = "number", default = 100 }, }
            },
        }, },
    },
}
