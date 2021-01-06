-- hello-world.handlar.lua
local BasePlugin = require "kong.plugins.base_plugin"
local cjson = require "cjson"
local EurekaServiceDiscovery= require "kong.plugins.eureka-service-bridge.eurekaservicediscovery"
local ServerBridge = BasePlugin:extend()
ServerBridge.VERSION = "1.0.0"
ServerBridge.PRIORITY = 10


-- 插件构造函数
function ServerBridge:new()
    ServerBridge.super.new(self, "eureka-service-bridge")
    kong.log.notice("-----eureka-service-bridge-new----starting--")
end

function ServerBridge:init_worker()
    ServerBridge.super.init_worker(self)
    -- 在这里实现自定义的逻辑
    kong.log.notice("-----eureka-service-bridge-init_worker----starting--")
    EurekaServiceDiscovery.starting()
end


return ServerBridge

