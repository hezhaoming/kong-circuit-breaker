-- Circuit Breaker   熔断 降级，失败率
-- 熔断对象
local BasePlugin = require "kong.plugins.base_plugin"
local CircuitBreaker = require "kong.plugins.circuit-breaker.circuitbreaker"
local cjson = require "cjson"

local CircuitBreakerHandler = BasePlugin:extend()
CircuitBreakerHandler.VERSION = "1.1.1"
CircuitBreakerHandler.PRIORITY = 10

-- api 接口前缀
local CIRCUIT_BREAKER_URL_PRE_KEY = "circuit_breaker"

-- 插件构造函数
function CircuitBreakerHandler:new()
    CircuitBreakerHandler.super.new(self, "circuit-breaker")
end

function CircuitBreakerHandler:access(conf)
    CircuitBreakerHandler.super.access(self)
    -- 幂等插入熔断器
    local cb = CircuitBreaker.insert_circuit_breaker(conf, CircuitBreakerHandler.get_circuit_breaker_key())
    --进行api熔断降级
    cb:run(conf)
end
-- 统计各种错误信息
function CircuitBreakerHandler:log(conf)
    CircuitBreakerHandler.super.log(self)
    print("\n" .. "<<<<当前配置conf" .. cjson.encode(conf) .. ">>>".."\n")
    -- 请求使用时间
    local http_request_time = tonumber(ngx.now() - ngx.req.start_time()) * 1000
    -- 请求响应状态
    local response_status = kong.response.get_status()
    -- 获取这个url的熔断器
    local cb = CircuitBreaker.get_circuit_breaker(CircuitBreakerHandler.get_circuit_breaker_key())
    if cb then
        --上报数据
        cb:set_metrics(conf, http_request_time, response_status)
        -- 执行熔断策略
        cb:is_exec_circuit_breaker(conf, http_request_time, response_status)
    end
end


-- 获取api 断路器的key
function CircuitBreakerHandler.get_circuit_breaker_key()
    --生成url of key
    local circuit_key = CIRCUIT_BREAKER_URL_PRE_KEY .. ngx.var.request_uri:gsub("?.*", ""):gsub("/[0-9]*$", "")
    return circuit_key
end

return CircuitBreakerHandler