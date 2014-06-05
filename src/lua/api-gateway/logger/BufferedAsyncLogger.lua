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
-- Specifies the amount of time in seconds since last flush
-- when the metrics should be flused, even if the buffer is not full
-----------------------------------------------------------------------------
local DEFAULT_FLUSH_INTERVAL = 5

local backendInst
local awsIAMCredentials = require "api-gateway.aws.AWSIAMCredentials"
local iamCredentialGenerator

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
    iamCredentialGenerator = awsIAMCredentials:new(self.logerSharedDict)

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

    -- decide if it's time to flush or not
    local lastFlushTimestamp = self.logerSharedDict:get("lastFlushTimestamp")
    if ( lastFlushTimestamp == nil) then
        lastFlushTimestamp = ngx.now()
        self.logerSharedDict:set("lastFlushTimestamp", lastFlushTimestamp)
    end
    if ( count >= self.flush_length or self.flush_interval < (ngx.now() - lastFlushTimestamp) ) then
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
    local logs_c = 0
    local keys = allMetrics:get_keys(self.flush_length)

    for i,metric in pairs(keys) do
        if (metric ~= "counter" and metric ~= "pendingTimers" and metric ~= "lastFlushTimestamp") then
            --mark item as expired
            local v = allMetrics:get(metric)
            if ( v ~= -10 ) then
                logs[metric] = v
                logs_c = logs_c + 1
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

    return logs, logs_c
end

-- Function to handle error from SNS
local function handleLoggingToSNSFailure(logs,number_of_logs)

    -- 400 : IncompleteSignature/InvalidAction/InvalidParameterCombination/InvalidParameterValue/
    -- 400 : InvalidQueryParameter/MissingAction/MissingParameter/RequestExpired/Throttling/ValidationError
    -- 403: InvalidClientTokenId/MissingAuthenticationToken/OptInRequired
    if(responseCode == 400 or responseCode == 403 ) then
        -- update the credentials
        iamCredentialGenerator:updateSecurityCredentials()

        -- retry sending data with new credentials
        local ok,responseCode = backendInst:sendLogs(logs)
        if(ok == 0) then
            ngx.log(ngx.ERR, "Alert!! Retried the 400 or 403 and failed again. SNS Error - " .. responseCode .. ". No of logs missed logging: " .. number_of_logs .. "!!!")
        end
    end

    -- MalformedQueryString - 404 | InternalFailure - 500 | ServiceUnavailable - 503
    if(responseCode == 404 or responseCode == 500 or responseCode == 503) then
        ngx.log(ngx.ERR, "Alert!! SNS MalformedQueryString -" .. responseCode .. ". No of logs missed logging: " .. number_of_logs .. "!!!")
    end

end


local function doFlushMetrics(premature, self)
    -- read the data and expire logs
    local logs, number_of_logs = self:getLogsFromSharedDict()
    if ( number_of_logs > 0 ) then
        -- call the backend
        local ok,responseCode = backendInst:sendLogs(logs)
        -- Handling failure cases of sending data to SNS
        if(ok == 0) then
            handleLoggingToSNSFailure(logs,number_of_logs)
        end
    end
    -- decremenet pendingTimers
    self.logerSharedDict:incr("pendingTimers", -1)
    -- save a timestamp of the last flush
    self.logerSharedDict:add("lastFlushTimestamp", ngx.now())
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


return AsyncLogger