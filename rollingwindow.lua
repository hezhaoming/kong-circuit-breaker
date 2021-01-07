-- 滑动窗口算法
local Rollingwindow = {}
Rollingwindow.__index = Rollingwindow
--初始化方法 窗口大小： metrics_rolling_size  ；时间粒度：metrics_granularity
function Rollingwindow.new(metrics_rolling_size, metrics_granularity)
    local self = setmetatable({  }, Rollingwindow)
    -- 初始化创建时间
    self._clock_at = os.time() * 1000
    -- 初始化窗口大小
    self.metrics_rolling_size = metrics_rolling_size
    -- 初始化时间粒度
    self.metrics_granularity = metrics_granularity
    -- 初始化数组,存请求错误的数量
    self._error_req_count = {}
    -- 初始化数组,存请求的数量
    self._api_req_count = {}
    -- 初始化窗口
    Rollingwindow.init_window(self)
    return self
end

-- 换钟
function Rollingwindow:shift (length)
    if length <= 0
    then
        return
    end
    -- 如果距离上一次的偏移的时间长度大于时间窗口，说明API太久没有访问过了（已经超过了 rolling_size * granularity的时间）
    -- 直接清空重新计算
    if length > self.metrics_rolling_size then
        -- 重新初始化窗口
        Rollingwindow.init_window(self)
    end
    --向前滑动 length格
    self._error_req_count = self.move_forward_len(self._error_req_count, length)
    self._api_req_count = self.move_forward_len(self._api_req_count, length)
end
--换钟
function Rollingwindow:shift_on_clock_changes ()
    -- 获取这次请求消耗的时间
    local pass_time = os.time() * 1000 - self._clock_at
    -- 是否超过时间粒度，超过则需要换钟，即向前滑动length格
    local length = math.modf(pass_time / self.metrics_granularity)
    -- 如果时间大于时间粒度，则需要滑动
    if length > 0 then
        self:shift(length)
        --重新记录滑动时间
        self._clock_at = os.time() * 1000
    end

end

-- 增加
function Rollingwindow:incr(api_req_num, error_req_num)
    -- 换钟：向前滑动，更新时钟
    self:shift_on_clock_changes()
    local err_len = #self._error_req_count
    self._error_req_count[err_len] = error_req_num + self._error_req_count[err_len]
    local api_len = #self._api_req_count
    self._api_req_count[api_len] = api_req_num + self._api_req_count[api_len]
end

-- api调用统计
function Rollingwindow:api_count()
    local res = 0
    for i = 1, #self._api_req_count do
        res = res + self._api_req_count[i]
    end
    return res
end

-- 错误统计
function Rollingwindow:error_count()
    local res = 0
    for i = 1, #self._error_req_count do
        res = res + self._error_req_count[i]
    end
    return res
end

--生成一个空的数组
function Rollingwindow.init_clear_array (size)
    local arr = {}
    for i = 1, size do
        table.insert(arr, 1, 0)
    end
    return arr
end

-- 初始化窗口
function Rollingwindow.init_window(self)
    self._error_req_count = Rollingwindow.init_clear_array(self.metrics_rolling_size)
    self._api_req_count = Rollingwindow.init_clear_array(self.metrics_rolling_size)
    print("\n" .. "清空统计数据" .. "\n")
    --  print("\n" .. "<<<<init_window 清空统计---api访问量：{ " .. self:api_count() .. " } error_req访问量{ " .. self:error_count() " } >>>>" .. "\n")
end

-- 向前移动 len 个窗口
function Rollingwindow.move_forward_len(arr, len)
    local new_arr = {}
    local index = 1
    for i = 1, #arr do
        --跳过小于len的窗口，插入后面的数据
        if (i > len) then
            table.insert(new_arr, index, arr[i])
            index = index + 1
        end
    end
    local pre_len = #new_arr
    -- 后面的窗口用0补齐
    for i = 1, len do
        table.insert(new_arr, pre_len + 1, 0)
    end
    return new_arr
end

function Rollingwindow.sleep(n)
    os.execute("sleep " .. n)
end

function Rollingwindow.prt(str, list)
    print(str .. table.concat(list, ",", 1))
end

-- 测试方法
--function main()
--    local rolling = Rollingwindow:new(5, 3000)
--    for i = 1, 100 do
--        Rollingwindow.sleep(1)
--        if i == 15 then
--            Rollingwindow.sleep(20)
--        end
--        --每次10个请求，生成一个错误的请求
--        rolling:incr(10, 1)
--        print("-------" .. i .. "------")
--        Rollingwindow.prt("错误统计", rolling._error_req_count)
--        Rollingwindow.prt("api调用统计", rolling._api_req_count)
--    end
--end
--
--main()

return Rollingwindow


