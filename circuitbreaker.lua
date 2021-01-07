local SlidingWindow = require "kong.plugins.circuit-breaker.rollingwindow"

local CircuitBreaker = {}
CircuitBreaker.__index = CircuitBreaker
CircuitBreaker.circuit_breaker_map = {}

-- 熔断器状态
local circuit_status = {
    CIRCUIT_STATUS_CLOSE = 0,
    CIRCUIT_STATUS_OPEN = 1,
    CIRCUIT_STATUS_HALF = 2
}

-- 响应状态
local DEFAULT_RESPONSE = {
    [401] = "Unauthorized",
    [404] = "Not found",
    [405] = "Method not allowed",
    [429] = "我要熔断",
    [500] = "An unexpected error occurred",
    [502] = "Bad Gateway",
    [503] = "Service unavailable",
}

-- 初始化  system插件名称
function CircuitBreaker.init(conf)
    local self = setmetatable({  }, CircuitBreaker)
    self.systemName = conf.systemName
    --降级回调接口
    self.api_call_back = conf.api_call_back
    --接口超时时间，毫秒
    self.api_request_timeout_ms = conf.api_request_timeout_ms
    -- 滑动窗口大小
    self.metrics_rolling_size = conf.metrics_rolling_size
    -- 时间粒度
    self.metrics_granularity = conf.metrics_granularity
    -- 请求出错比例 [0-100]
    self.metrics_error_ratio = conf.metrics_error_ratio
    -- 熔断器存活默认15秒，就变成半开状态
    self.min_recovery_time_ms = conf.min_recovery_time_ms
    -- 熔断请求的数量，大于一定的请求量，才有熔断的意义
    self.threshold_request_count = conf.threshold_request_count
    --滑动窗口
    self.window = SlidingWindow.new(conf.metrics_rolling_size, conf.metrics_granularity)
    --熔断器状态- 关闭熔断
    self.circuit_status = circuit_status.CIRCUIT_STATUS_CLOSE
    -- 熔断器开始时间
    self.open_at = 0
    -- 定义普罗米斯监控 prometheus指标
    --  self.prometheus_circuit_status = prometheus:gauge("circuit_status", "断路器状态，0 CLOSE,1 OPEN,2 HALF,3 CHECK", { "system", "url" })
    --  self.prometheus_circuit_times = prometheus:counter("circuit_times", "熔断次数", { "system", "url" })
    return self
end

-- access 层做处理
function CircuitBreaker:run(conf)
    print("\n" .. "<<<<熔断状态：{ " .. self.circuit_status .. " } opentime:{ " .. self.open_at .. " } >>>>" .. "\n")
    -- 如果熔断打开则需要走熔断降级逻辑
    if self.circuit_status == circuit_status.CIRCUIT_STATUS_OPEN then
        -- 如果配置降级接口，走降级接口
        if conf.api_call_back then
            local resp = ngx.location.capture(conf.api_call_back, {
                method = ngx.HTTP_GET,
                args = { q = "hello"}
            })
            if not resp then
                ngx.say("request error :", err)
                return
            end
            ngx.log(ngx.ERR, tostring(resp.status))
            --获取状态码
            ngx.status = resp.status

            --获取响应头
            for k, v in pairs(resp.header) do
                if k ~= "Transfer-Encoding" and k ~= "Connection" then
                    ngx.header[k] = v
                end
            end
            --响应体
            if resp.body then
                ngx.say(resp.body)
            end
        else
            --否则走熔断接口
            local status = conf.status
            local content = conf.body
            if content then
                local headers = {
                    ["Content-Type"] = conf.content_type
                }
                return kong.response.exit(status, content, headers)
            end
            local message = conf.message or DEFAULT_RESPONSE[conf.status]
            return kong.response.exit(status, message and { message = message } or nil)
        end
    end
end

-- 上报访问结果
function CircuitBreaker:set_metrics(conf, http_request_time, response_status)
    print("\n" .. "<<<<metric-pre api访问量：{ " .. self.window:api_count() .. " } error_req访问量{ " .. self.window:error_count() .. " } >>>>" .. "\n")
    local window = self.window
    -- 请求失败 or 请求超时
    if response_status ~= 200 or http_request_time > conf.api_request_timeout_ms then
        -- 请求失败
        window:incr(1, 1)
    else
        -- 请求成功
        window:incr(1, 0)
    end
    print("\n" .. "<<<<metric-post api访问量：{ " .. self.window:api_count() .. " } error_req访问量{ " .. self.window:error_count() .. " } >>>>" .. "\n")
end
-- 是否走熔断降级
function CircuitBreaker:is_exec_circuit_breaker(conf, http_request_time, response_status)
    -- 如果熔断器目前是close,则需要判断是否需要开启熔断
    if self.circuit_status == circuit_status.CIRCUIT_STATUS_CLOSE then
        -- 如果api不健康
        if self:api_not_health(conf) then
            -- 开启熔断
            self.circuit_status = circuit_status.CIRCUIT_STATUS_OPEN
            self['open_at'] = os.time() * 1000
            return true
        end
        return false
    end
    -- 如果熔断器目前是open,则需要判断,是否需要关闭熔断，
    if self.circuit_status == circuit_status.CIRCUIT_STATUS_OPEN then
        -- 如果熔断恢复期已经到来则去尝试一下
        print('时间' .. os.time() * 1000 - self.open_at .. "配置时间" .. conf.min_recovery_time_ms)
        if os.time() * 1000 - self.open_at > conf.min_recovery_time_ms then
            -- 如果当前api是不行OK的，那么变成半开
            if self:current_api_not_health(conf, http_request_time, response_status) then
                -- 半开熔断
                self.circuit_status = circuit_status.CIRCUIT_STATUS_HALF
                self['open_at'] = os.time() * 1000
                return false
            else
                -- 否则恢复
                self.circuit_status = circuit_status.CIRCUIT_STATUS_CLOSE
                -- 情况统计数据
                Rollingwindow.init_window(self.window)
                self['open_at'] = 0;
                return true
            end
        end
        return false
    end
    -- 如果熔断器目前是half,则需要判断当前请求是否成功
    if self.circuit_status == circuit_status.CIRCUIT_STATUS_HALF then
        --请求成功即恢复
        if not self:current_api_not_health(conf, http_request_time, response_status) then
            self.circuit_status = circuit_status.CIRCUIT_STATUS_CLOSE
            -- 情况统计数据
            Rollingwindow.init_window(self.window)
            self['open_at'] = 0;
            return true
        else
            self.circuit_status = circuit_status.CIRCUIT_STATUS_OPEN
            self['open_at'] = os.time() * 1000;
            return false
        end

    end
end

-- 判断api是否健康
-- 判断熔断的条件,即只有当请求的数量大于某一个值才开始检测API的状态
-- 1.请求量大于一个阈值请求量
-- 2. 超时次数/总请求次数
-- 3. 健康请求次数/总请求次数
-- 4. 失败请求次数/总请求次数
function CircuitBreaker:api_not_health(conf)
    local api_count = self.window:api_count()
    local error_count = self.window:error_count()
    --目前设计了两个条件：连续访问量达到一定的阈值，访错率到达一定比率
    print("\n" .. "<<<<失败比例:{ " .. (error_count / api_count) .. "} ---配置阈值比例：{ " .. (conf.metrics_error_ratio / 100) .. "} >>>" .. "\n")
    if api_count >= conf.threshold_request_count and error_count / api_count >= conf.metrics_error_ratio / 100 then
        return true
    end
    return false
end
-- 判断当前api是否健康
function CircuitBreaker:current_api_not_health(conf, http_request_time, response_status)
    local bool = (response_status ~= 200 or http_request_time > conf.api_request_timeout_ms)
    print("\n" .. "<<<<判断当前api=[response_status=" .. response_status .. "---http_request_time:" .. http_request_time .. "]是否健康:" .. tostring(bool) .. ">>>" .. "\n")
    --超时或者访问失败
    if bool then
        return true
    end
    return false
end

-----------------------工具类-------------------------------
-- 获取断路器
function CircuitBreaker.get_circuit_breaker(key)
    return CircuitBreaker.circuit_breaker_map[key]
end
-- 为api插入断路器
function CircuitBreaker.insert_circuit_breaker(conf, key)
    -- kong.log.notice("------access insert_circuit_breaker key----", key)
    -- 判断是否存在断路器
    local circuitBreaker = CircuitBreaker.circuit_breaker_map[key]
    -- kong.log.notice("------access insert_circuit_breaker api_call_back----", circuitBreaker)
    -- 如果不存在则插入断路器
    if circuitBreaker == nil then
        --插入该api断路器
        circuitBreaker = CircuitBreaker.init(conf)
    end
    -- kong.log.notice("------access insert_circuit_breaker key----", circuitBreaker.api_call_back)
    --插入map中
    CircuitBreaker.circuit_breaker_map[key] = circuitBreaker
    return circuitBreaker
end

function CircuitBreaker.test()
    CircuitBreaker.circuit_breaker_map["yanyulou"] = {
        name = "烟雨楼",
        sex = 2
    }
    return CircuitBreaker.circuit_breaker_map
end
return CircuitBreaker