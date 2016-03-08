--[[
  Copyright (c) 2016. Adobe Systems Incorporated. All rights reserved.

    This file is licensed to you under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License is
    distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR RESPRESENTATIONS OF ANY KIND,
    either express or implied.  See the License for the specific language governing permissions and
    limitations under the License.

  ]]

--
-- A Lua module to be used for logging data asynchronously.
-- The module buffers data into a shared dictionary to persist it when nginx reloads.
-- When the buffer is full or when the flush interval expires, logs are sent to the backend.
--
-- This module allows you to bring your own backend implementation, passed as "backend" parameter to the init object.
--  The only method that the backend needs to implement is `sendLogs(logs)`
--
-- User: ddascal
-- Date: 15/05/14
--

--
local AsyncLogger = {}

---
-- The length of the buffer. When the number of logs reaches this number
-- they will be flushed
local DEFAULT_BUFFER_LENGTH = 10
---
-- Specifies how many concurrent background threads to use to flush data
local DEFAULT_CONCURRENCY = 3

---
-- Specifies the maximum time in seconds since last flush
-- after which the metrics would be flushed out regardless if the buffer is not full
local DEFAULT_FLUSH_INTERVAL = 5


function AsyncLogger:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    if (o ~= nil) then
        local s = ""
        for k,v in pairs(o) do
            s = s .. ", " .. k .. "=" .. tostring(v)
        end
        ngx.log(ngx.DEBUG, "BufferedAsyncLogger(): init object=" .. s)

        o.flush_length = o.flush_length or DEFAULT_BUFFER_LENGTH
        o.logerSharedDict = ngx.shared[o.sharedDict]
        o.flush_concurrency = o.flush_concurrency or DEFAULT_CONCURRENCY
        o.flush_interval = o.flush_interval or DEFAULT_CONCURRENCY

        local backendCls = assert(require(o.backend), "please provide a valid backend class name")
        o.backendInst = backendCls:new(o.backend_opts)
    end

    ngx.log(ngx.DEBUG, "Initialized new async logger with backend ", tostring(o.backend), " instance:", tostring(o.backendInst))

    return o
end

-- Save the data into shared dict
function AsyncLogger:logMetrics(key, value)
    if (self.logerSharedDict == nil) then
        ngx.log(ngx.ERR, "Please define 'lua_shared_dict ", tostring(self.sharedDict), " 50m;' in http block")
        return nil
    end
    --value = toString(value) or ""
    if tostring(value) == "" or value == nil
            or tostring(key) == "" or key == nil then -- to exit when nil/zero
        ngx.log(ngx.ERR, "Could not log metric with key=" .. tostring(key) .. ", value=" .. tostring(value))
        return 0
    end

    ngx.log(ngx.DEBUG, "adding new metric. key=", tostring(key), ", value=", tostring(value))

    -- count the number of values in the shared dict and flush when its full
    local count = self.logerSharedDict:incr("counter", 1)
    if (count == nil) then
        self.logerSharedDict:add("counter", 1)
        count = 1
    end

    -- add the key and value
    local status = self.logerSharedDict:add(key, value)

    -- decide if it's time to flush or not
    local lastFlushTimestamp = self.logerSharedDict:get("lastFlushTimestamp")
    if (lastFlushTimestamp == nil) then
        lastFlushTimestamp = ngx.now()
        self.logerSharedDict:set("lastFlushTimestamp", lastFlushTimestamp)
    end

    local is_buffer_full = (count >= self.flush_length)
    local time_since_last_flush = (ngx.now() - lastFlushTimestamp)
    local is_flush_interval_expired = (self.flush_interval < time_since_last_flush)

    if (is_buffer_full or is_flush_interval_expired) then
        ngx.log(ngx.DEBUG, "Flushing metrics. is_buffer_full=", tostring(is_buffer_full),
            " , is_flush_interval_expired=", tostring(is_flush_interval_expired),
            " , time_since_last_flush=", tostring(time_since_last_flush))
        self:flushMetrics()
    else
        ngx.log(ngx.DEBUG, "Metrics not flushed. is_buffer_full=", tostring(is_buffer_full),
            " , is_flush_interval_expired=", tostring(is_flush_interval_expired),
            " , time_since_last_flush=", tostring(time_since_last_flush))
    end

    return status
end

-- returns the buffered logs and clears the dict
function AsyncLogger:getLogsFromSharedDict()

    -- convert shared_dict to table
    local allMetrics = self.logerSharedDict
    if (allMetrics == nil) then
        return nil
    end
    local logs = {}
    local logs_c = 0
    local keys = allMetrics:get_keys(self.flush_length)

    for i, metric in pairs(keys) do
        if (metric ~= "counter" and metric ~= "pendingTimers"
                and metric ~= "lastFlushTimestamp"
                and metric ~= "AccessKeyId"
                and metric ~= "SecretAccessKey"
                and metric ~= "Token"
                and metric ~= "ExpireAt"
                and metric ~= "ExpireAtTimestamp") then
            --mark item as expired
            local v = allMetrics:get(metric)
            logs[metric] = v
            logs_c = logs_c + 1
            allMetrics:delete(metric)
        end
    end

    local dict_counter = self.logerSharedDict:get("counter")
    local remaining_count = 0
    if (dict_counter > self.flush_length) then
        remaining_count = dict_counter - self.flush_length
    end
    if (remaining_count ~= dict_counter) then
        self.logerSharedDict:set("counter", remaining_count)
    end

    -- TODO: consider exposing the flush_expired method
    allMetrics:flush_expired()

    return logs, logs_c
end

local function tableToString(table_ref)
    local s = ""
    local o = table_ref or {}
    for k, v in pairs(o) do
        s = s .. ", " .. k .. "=" .. tostring(v)
    end
    return s
end

local function doFlushMetrics(premature, self)
    ngx.log(ngx.DEBUG, "Flushing metrics with premature flag:", premature, " to backend:", tostring(self.backend), " self=", tostring(tableToString(self)) )
    -- decremenet pendingTimers
    self.logerSharedDict:incr("pendingTimers", -1)
    -- save a timestamp of the last flush
    self.logerSharedDict:set("lastFlushTimestamp", ngx.now())

    -- read the data and expire logs
    local logs, number_of_logs = self:getLogsFromSharedDict()
    if (number_of_logs > 0) then
        -- call the backend
        local ok, responseCode, headers, status, body, failedRecords = self.backendInst:sendLogs(logs)

        -- Handling failure cases
        -- 1. Check if the backend responded OK
        if (responseCode ~= 200) then
            ngx.log(ngx.WARN, "Failed to send ", tostring(number_of_logs), " logs to the backend. Saving them for later in the shared dict ...")
            -- add metrics back
            for k,v in pairs(logs) do
                -- add each metric back into the dict
                self:logMetrics(k,v)
            end
        end

        -- 2. Check if the backend rejected some logs ( this could be due to rate limits )
        --    in this case it's the backend's resposibility to return which logs have failed
        local logsToResendCounter = 0
        if (failedRecords ~= nil) then
            for k,v in pairs(failedRecords) do
                -- add each metric back into the dict
                self:logMetrics(k,v)
                logsToResendCounter = logsToResendCounter + 1
            end
        end
        if (logsToResendCounter > 0) then
            ngx.log(ngx.WARN, "Resending: ", tostring(logsToResendCounter), " out of " , tostring(number_of_logs) , " logs again.")
        end

        return
    end
    ngx.log(ngx.WARN, "Could not flush metrics to backend ", tostring(self.backend) , " number_of_logs=", tostring(number_of_logs) )
end

-- Send data to a backend.
function AsyncLogger:flushMetrics()
    local concurrency = self.logerSharedDict:get("pendingTimers")
    if (concurrency == nil or concurrency < 0) then
        concurrency = 0
        self.logerSharedDict:set("pendingTimers", 0)
    end
    if (concurrency < self.flush_concurrency) then
        -- pick a random delay between 10ms to 100ms when to spawn this timer
        local delay = math.random(10, 100)
        local ok, err = ngx.timer.at(delay / 1000, doFlushMetrics, self)
        if not ok then
            ngx.log(ngx.WARN, "Could not flushMetrics this time, will retry later. Details: ", err)
            return false
        end
        ngx.log(ngx.DEBUG, "Scheduling flushMetrics in " .. tostring(delay) .. "ms.")
        -- at this point we're certain the timer has started successfully
        self.logerSharedDict:incr("pendingTimers", 1)
        return true
    end
    -- concurrency limit is reached at this point, no more thread is spawn
    return false
end


return AsyncLogger