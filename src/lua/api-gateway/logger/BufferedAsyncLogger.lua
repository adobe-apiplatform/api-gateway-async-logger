--
-- Created by IntelliJ IDEA.
-- User: ddascal
-- Date: 15/05/14
-- Time: 15:08
-- To change this template use File | Settings | File Templates.
--

-- Class for logging data asynch
local AsyncLogger = {}

local DEFAULT_BUFFER_LENGTH = 10

local backendInst

function AsyncLogger:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    self.flush_length = DEFAULT_BUFFER_LENGTH

    if ( o ~= nil) then
        self.flush_length = o.flush_length
        self.logerSharedDict = ngx.shared[o.sharedDict]
        self.backend = o.backend
        self.backend_opts = o.backend_opts

        local backendCls = assert(require(o.backend), "please provide a valid backend class name" )
        backendInst = backendCls:new(self.backend_opts)
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
    local count = self.logerSharedDict:incr("counter", 1)
    if ( count == nil ) then
        self.logerSharedDict:add("counter", 1)
    end

    -- add the key and value
    local status = self.logerSharedDict:add(key, value)

    -- start flushing the shared dict when the count reaches 600
    if(count == self.flush_length) then
        self:flushMetrics()
    end

    return status
end

-- returns the buffered logs and clears the dict
function AsyncLogger:getLogsFromSharedDict()

 -- convert shared_dict to table
    local allMetrics = self.logerSharedDict
    if ( allMetrics == nil ) then
        return nil
    end
    self.logerSharedDict:set("counter", 0)
    local logs = {}
    local keys = allMetrics:get_keys(self.flush_length)

    for i,metric in pairs(keys) do
        if(metric ~= "counter") then
            --mark item as expired
            logs[metric] = allMetrics:get(metric)
            allMetrics:set(metric, 0, 0.001,0)
        end
    end

    -- TODO: consider exposing the flush_expired method
    allMetrics:flush_expired()

    return logs
end

-- Send data to a backend.
function AsyncLogger:flushMetrics()
    --1. read the data and expire logs
    local logs = self:getLogsFromSharedDict()
    --2. call the backend
     backendInst:sendLogs(logs)
end



function AsyncLogger:getDataFromSharedDict( flushExpiredMetrics )

    --    local value
    --    local jsonString = ""
    --    for i,metric in pairs(keys) do
    --        if(metric ~= "counter") then
    --            value = allMetrics:get(metric)
    --            --mark item as expired
    --            allMetrics:set(metric, 0, 0.001,0)
    --            jsonString  = jsonString .. "[" .. value .. "],"
    --        end
    --    end
    --    --remove the last "," from the jsonString
    --    jsonString = string.sub(jsonString, 1, -2)


--    local MetricsCls = require "api-gateway.core.metrics"
--    local metrics = MetricsCls:new()
--    local req_body = metrics:toJsonForAnalyticsSNS()
--    return req_body


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

return AsyncLogger