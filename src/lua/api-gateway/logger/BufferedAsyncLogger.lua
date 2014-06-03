--
-- Created by IntelliJ IDEA.
-- User: ddascal
-- Date: 15/05/14
-- Time: 15:08
-- To change this template use File | Settings | File Templates.
--

-- Class for logging data asynch
local AsyncLogger = {}

-----------------------------------------------------------------------------
-- The length of the buffer. When the number of logs reaches this number
-- they will be flushed
-----------------------------------------------------------------------------
local DEFAULT_BUFFER_LENGTH = 10
-----------------------------------------------------------------------------
-- Specifies how many concurrent background threads to the used to flush data
-----------------------------------------------------------------------------
local DEFAULT_CONCURRENCY = 3
-----------------------------------------------------------------------------
-- Specifies the amount of time since last flush when the metrics should be
-- flused, even if the buffer is not full
-----------------------------------------------------------------------------
local DEFAULT_FLUSH_INTERVAL = 5

local backendInst

function AsyncLogger:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    if ( o ~= nil) then
        self.flush_length = o.flush_length or DEFAULT_BUFFER_LENGTH
        self.logerSharedDict = ngx.shared[o.sharedDict]
        self.backend = o.backend
        self.backend_opts = o.backend_opts
        self.flush_concurrency = o.flush_concurrency or DEFAULT_CONCURRENCY
        self.flush_interval = o.flush_interval or DEFAULT_CONCURRENCY

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
    if tostring(value) == "" or value == nil
      or tostring(key) == "" or key == nil then -- to exit when nil/zero
        ngx.log(ngx.WARN, "Could not log metric with key=" .. tostring(key) .. ", value=" .. tostring(value))
        return 0
    end

    -- count the number of values in the shared dict and flush when its full
    local count = self.logerSharedDict:incr("counter", 1)
    if ( count == nil ) then
        self.logerSharedDict:add("counter", 1)
        count = 1
    end

    -- add the key and value
    local status = self.logerSharedDict:add(key, value)

    -- start flushing the shared dict when the count reaches 600
    -- TODO: b/c flushing the logs is async, count > self.flush_length would be TRUE for consecutive calls until timer executes
    -- one idea would be to take into account the pending timers
    if(count >= self.flush_length) then
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
    local logs = {}
    local keys = allMetrics:get_keys(self.flush_length)

    for i,metric in pairs(keys) do
        if (metric ~= "counter" and metric ~= "pendingTimers") then
            --mark item as expired
            local v = allMetrics:get(metric)
            if ( v ~= -10 ) then
                logs[metric] = v
            end
            allMetrics:set(metric, -10, 0.001,0)
        end
    end

    local dict_counter = self.logerSharedDict:get("counter")
    local remaining_count = 0
    if ( dict_counter > self.flush_length ) then
        remaining_count = dict_counter - self.flush_length
    end
    if ( remaining_count ~= dict_counter ) then
        self.logerSharedDict:set("counter", remaining_count)
    end

    -- TODO: consider exposing the flush_expired method
    allMetrics:flush_expired()

    return logs
end

local function doFlushMetrics(premature, self)
    --1. read the data and expire logs
    local logs = self:getLogsFromSharedDict()
    --2. call the backend
     backendInst:sendLogs(logs)
    --3. decremenet pendingtimers
    self.logerSharedDict:incr("pendingTimers", -1)
end

-- Send data to a backend.
function AsyncLogger:flushMetrics()
    local concurrency = self.logerSharedDict:get("pendingTimers")
    if ( concurrency == nil or concurrency < 0 ) then
        concurrency = 0
        self.logerSharedDict:set("pendingTimers",0)
    end
    if ( concurrency < self.flush_concurrency) then
        -- pick a random delay between 10ms to 100ms when to spawn this timer
        local delay = math.random(10,100)
        ngx.timer.at(delay/1000, doFlushMetrics, self)
        self.logerSharedDict:incr("pendingTimers", 1)
        return true
    end
    -- concurrency limit is reached at this point, no more thread is spawn
    return false
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