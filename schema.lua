return {
    name = "eureka-service-bridge",
    fields = {
        {
            config = {
                type = "record",
                fields = {
                    {eureka_url = {type = "string"}},
                    {sync_interval = {type = "number", default = 30}},
                    {clean_target_interval = {type = "number", default = 86400}}
                }
            }
        }
    }
}
