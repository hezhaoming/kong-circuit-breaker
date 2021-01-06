local cjson = require "cjson"
local http = require "resty.http"
local ngx_re = require "ngx.re"
-- kong 管理工具类
local kongAdminOperation = require "kong.plugins.eureka-service-bridge.kongadminoperation"
-- 多个worker 共享的
local kong_cache = ngx.shared.kong
local pluginName = "eureka-service-bridge"
local eureka_suffix = 2
local METHOD_GET = "GET"
local cache_expire = 120
local sync_eureka_plugin = {}
local LOG_INFO = kong.log.info
local LOG_DEBUG = kong.log.debug
local LOG_ERROR = kong.log.err
local LOG_WARN = kong.log.warn
-- eureka 服务发现
local EurekaServiceDiscovery = {}
EurekaServiceDiscovery.__index = EurekaServiceDiscovery

-- https://github.com/Netflix/eureka/wiki/Eureka-REST-operations
local status_weight = {
    ["UP"] = 100,
    ["DOWN"] = 1,
    ["STARTING"] = 0,
    ["OUT_OF_SERVICE"] = 0,
    ["UNKNOWN"] = 1
}

--- fetch eureka applications info
local function eureka_apps(app_name)
    print("\n" .. "================开始拉取 eureka apps 服务列表...=================================")
    LOG_INFO("start fetch eureka apps [ ", app_name or "all", " ]")
    if not sync_eureka_plugin then
        return nil, 'failed to query plugin config'
    end
    local config = sync_eureka_plugin["enabled"] and sync_eureka_plugin["config"] or nil

    local httpClient = http.new()
    local res, err = httpClient:request_uri(config["eureka_url"] .. "/apps/" .. (app_name or ''), {
        method = METHOD_GET,
        headers = { ["Accept"] = "application/json" },
        keepalive_timeout = 60,
        keepalive_pool = 10
    })
    print("\n" .. "================开始拉取 eureka apps 服务列表...==============url====" .. config["eureka_url"] .. "/apps/" .. (app_name or ''))
    if not res then
        LOG_ERROR("failed to fetch eureka apps request: ", err)
        print("\n" .. "================开始拉取 eureka apps 失败...==============url====" .. err)
        return nil
    end
    local apps = cjson.decode(res.body)

    --[[
      convert to app_list  -- https://github.com/Netflix/eureka/wiki/Eureka-REST-operations
    {
      "demo":{
        "192.168.0.10:8080"="UP",
        "health_path"="/health"
      }
    }
  ]]

    if app_name then
        apps = { ["applications"] = { ["application"] = { apps["application"] } } }
    end

    local app_list = {}
    for _, item in pairs(apps["applications"]["application"]) do
        local name = string.lower(item["name"])
        app_list[name] = {}
        for _, it in pairs(item["instance"]) do
            local host, _ = ngx_re.split(it["homePageUrl"], "/")
            app_list[name][host[3]] = it['status']
            app_list[name]["health_path"] = string.sub(it["healthCheckUrl"], string.len(it["homePageUrl"]))
        end
    end

    LOG_DEBUG("end to fetch eureka apps,total of ", #app_list, " apps")
    return app_list
end

--- cron job to cleanup invalid targets
EurekaServiceDiscovery.cleanup_targets = function()
    LOG_DEBUG("cron job to cleanup invalid targets")
    sync_eureka_plugin = kongAdminOperation.getCurrentPlugin(pluginName)
    if not sync_eureka_plugin then
        return
    end
    local app_list = eureka_apps()
    local upstreams = kongAdminOperation.kong_upstreams() or {}
    for up_name, name in pairs(upstreams) do
        local targets = kongAdminOperation.get_targets(name, "/upstreams/" .. up_name .. "/targets") or {}
        -- delete all targets by this upstream name
        if not app_list[name] then
            for target, _ in pairs(targets) do
                kongAdminOperation.delete_target(name, target, eureka_suffix)
            end
        else
            for target, _ in pairs(targets) do
                -- delete this target
                if app_list[name][target] ~= "UP" then
                    kongAdminOperation.delete_target(name, target, eureka_suffix)
                end
            end
        end
    end
end

--- cron job to fetch apps from eureka server
EurekaServiceDiscovery.sync_job = function(app_name)
    LOG_INFO("cron job to fetch apps from eureka server [ ", app_name or "all", " ]")
    sync_eureka_plugin = kongAdminOperation.getCurrentPlugin(pluginName)
    if not sync_eureka_plugin then
        return
    end
    local cache_app_list = kong_cache:get("sync_eureka_apps") or "{}"
    cache_app_list = cjson.decode(cache_app_list)
    local app_list = eureka_apps(app_name)
    print("\n" .. "=================执行到的app_list...=================================" .. cjson.encode(app_list))
    for name, item in pairs(app_list) do
        if not cache_app_list[name] then
            kongAdminOperation.create_service(name, eureka_suffix)
            kongAdminOperation.create_route(name, eureka_suffix)
            kongAdminOperation.create_upstream(name, eureka_suffix)
        end

        cache_app_list[name] = true
        for target, status in pairs(item) do
            if target ~= "health_path" then
                kongAdminOperation.put_target(name, target, status_weight[status], { status }, eureka_suffix)
            end
        end
    end

    kong_cache:safe_set("sync_eureka_apps", cjson.encode(cache_app_list), cache_expire)
end

--- init worker
function EurekaServiceDiscovery:starting()
    if 0 ~= ngx.worker.id() then
        return
    end
    -- 拉取当前插件
    sync_eureka_plugin = kongAdminOperation.getCurrentPlugin(pluginName)
    if sync_eureka_plugin and sync_eureka_plugin["enabled"] then
        --定时拉取
        local ok, err = ngx.timer.every(sync_eureka_plugin["config"]["sync_interval"], EurekaServiceDiscovery.sync_job)
        if not ok then
            LOG_ERROR("failed to create the timer: ", err)
            return
        end
        --定时摘除
        local ok, err = ngx.timer.every(sync_eureka_plugin["config"]["clean_target_interval"], EurekaServiceDiscovery.cleanup_targets)
        if not ok then
            LOG_ERROR("failed to create the timer: ", err)
            return
        end
    end
end

return EurekaServiceDiscovery
