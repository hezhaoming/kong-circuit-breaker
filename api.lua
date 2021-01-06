local EurekaServiceDiscovery = require "kong.plugins.eureka-service-bridge.eurekaservicediscovery"
local write = kong.response.exit
return {
    ["/eureka/sync(/:app)"] = {
        POST = function(self)
            EurekaServiceDiscovery.sync_job(self.params.app)
            return write(200, { message = "sync eureka " .. (self.params.app or "all") .. " now ..." })
        end
    },
    ["/eureka/clean-targets"] = {
        POST = function()
            EurekaServiceDiscovery.cleanup_targets()
            return write(200, { message = "cleanup invalid targets ..." })
        end
    }
}
