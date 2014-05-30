--
-- Created by IntelliJ IDEA.
-- User: ddascal
-- Date: 15/05/14
-- Time: 15:08
-- To change this template use File | Settings | File Templates.
--

-- Class for logging data asynch
local AsyncLogger = {}

function AsyncLogger:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if ( o ~= nil) then
        self.flush_length = o.flush_length
        self.logerSharedDict = ngx.shared[o.sharedDict]
        self.flushDestination = o.flushDestination
    end
    return o
end

-- Save the data into shared dict
function AsyncLogger:logMetrics(key, value)
    if ( self.logerSharedDict == nil ) then
        ngx.log(ngx.ERR, "Please define 'lua_shared_dict stats_all 50m;' in http block")
        return nil
    end
    --value = toString(value) or ""
    if value == "" then -- to exit when nil/zero
        return 0
    end

    -- count the number of values in the shared dict and flush when its 600
    count = self.logerSharedDict:incr("counter", 1)
    if ( count == nil ) then
        self.logerSharedDict:add("counter", 1)
    end

    -- start flushing the shared dict when the count reaches 600
    if(count == self.flush_length) then
        self:flushMetrics()
    end

    -- add the key and value
    r = self.logerSharedDict:add(key, value)
    return r
end

-- Save the data into shared dict
function AsyncLogger:flushMetrics(location)
    local PostLogs = require "api-gateway.logger.PostLogs"
    local poster =  PostLogs:new()

    if(location ~= nil) then
        poster:postDataToInternalLocation(location)
        return
    end
    poster:postDataToAnalyticsSNS()
end

function AsyncLogger:getJsonFor( metric_type )
    -- convert shared_dict to table
    local allMetrics = ngx.shared[metric_type]
    if ( allMetrics == nil ) then
        return nil
    end
    local keys = allMetrics:get_keys(self.flush_length)
    local value
    local jsonString = ""
    for i,metric in pairs(keys) do
        if(metric ~= "counter") then
            value = allMetrics:get(metric)
            --mark item as expired
            allMetrics:set(metric, 0, 0.001,0)
            jsonString  = jsonString .. "[" .. value .. "],"
        end
    end
    --remove the last "," from the jsonString
    jsonString = string.sub(jsonString, 1, -2)

    -- reset the count of flush counter
    self.logerSharedDict:set("counter", 0)

    return jsonString
end

function AsyncLogger:getDataFromSharedDict( flushExpiredMetrics )
    local MetricsCls = require "api-gateway.core.metrics"
    local metrics = MetricsCls:new()
    local req_body = metrics:toJsonForAnalyticsSNS()
    return req_body

--    local values = self:getJsonFor("stats_all")
--    local flush = flushExpiredMetrics or true
--
--    local headings =  "\'publisher\',".."\'consumer\',".."\'application\',".."\'service\',".."\'region\',".."\'requestMethod\',".."\'status\',".. "\'guid\',"..
--            "\'guid\',".."\'timstamp\',".."\'ipAddress\',".."\'requestPath\'"
--
--    if ( flush == true ) then
--        self:flushExpiredKeys()
--    end
--    return "{\"headings\":[" .. headings .. "],\"values\":[" .. values .. "]}", counterObject, timerObject
end

function AsyncLogger:flushExpiredKeys()
    local metrics = ngx.shared.stats_all
    if ( metrics ~= nil ) then
        metrics:flush_expired()
    end
end

return AsyncLogger