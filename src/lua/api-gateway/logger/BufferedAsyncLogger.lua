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

local lock_cls = require "resty.lock"

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
-- after which the metrics would be flushed out regardless if the buffer full or not
local DEFAULT_FLUSH_INTERVAL = 5

---
-- Specifies the maximum throughput per seconds for sending logs
--
local DEFAULT_FLUSH_THROUGHPUT = 1000000


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
        o.flush_throughput = o.flush_throughput or DEFAULT_FLUSH_THROUGHPUT

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

    if(self:shouldFlush()) then
        self:flushMetrics()
    end

    return status
end

--- Returns the number of logs as tracked in the "counter" element of the shared dictionary.
--   This number should match the total number of items in the shared dictionary
function AsyncLogger:getCount()
    local count = self.logerSharedDict:get("counter")
    if (count == nil) then
        self.logerSharedDict:add("counter", 0)
        count = 0
    end
    return count
end

--- Decides if it's time to flush or not
-- This method returns true if one the following is true:
--   1. the number of logs is greater than the flush_length
--   2. the time since last flush is greater than flush_interval
--   3. the throughput is not exceeded
function AsyncLogger:shouldFlush()
    local count = self:getCount()
    local lastFlushTimestamp = self.logerSharedDict:get("lastFlushTimestamp")
    if (lastFlushTimestamp == nil) then
        lastFlushTimestamp = ngx.now()
        -- add method only sets the key if it doesn't exist
        self.logerSharedDict:add("lastFlushTimestamp", lastFlushTimestamp)
    end

    -- also take into account any pending threads already scheduled
    local pending_threads = self.logerSharedDict:get("pending_threads")
    -- an approximate number of logs that could be sent by the pending threads
    local possible_extra_logs = (pending_threads or 0) * self.flush_length

    local current_throughput = self.logerSharedDict:get("throughput_counter")
    if (current_throughput == nil) then
        current_throughput = 0
        local secs = ngx.now() --the elapsed time in seconds (including milliseconds as the decimal part) from the epoch
        local ms_to_sec = secs - math.floor(secs) -- compute how long until the current second expires
        local exptime = 1 - ms_to_sec
        -- don't track the throughput when there's 50ms left from the current second
        if ( exptime > 0.050) then
            -- add method only sets the key if it doesn't exist
            self.logerSharedDict:add("throughput_counter", current_throughput, exptime)
        end
    end

    local is_buffer_full = (count >= self.flush_length + possible_extra_logs)
    local time_since_last_flush = (ngx.now() - lastFlushTimestamp)
    local is_flush_interval_expired = (self.flush_interval < time_since_last_flush)

    local is_throughput_exceeded = false
    if (current_throughput + possible_extra_logs >= self.flush_throughput) then
        is_throughput_exceeded = true
    end

    if ((is_buffer_full or is_flush_interval_expired) and is_throughput_exceeded == false) then
        ngx.log(ngx.DEBUG, "Flushing metrics. is_buffer_full=", tostring(is_buffer_full),
            " , is_flush_interval_expired=", tostring(is_flush_interval_expired),
            " , time_since_last_flush=", tostring(time_since_last_flush),
            " , is_throughput_exceeded=", tostring(is_throughput_exceeded)
        )
        return true
    else
        ngx.log(ngx.DEBUG, "Metrics not flushed. is_buffer_full=", tostring(is_buffer_full),
            " , is_flush_interval_expired=", tostring(is_flush_interval_expired),
            " , time_since_last_flush=", tostring(time_since_last_flush),
            " , is_throughput_exceeded=", tostring(is_throughput_exceeded)
        )
        return false
    end
end

--- Returns the logs from the shared dict
--    A number of flush_length logs are returned, unless the throughput in the current second has exceeded
--    If the flush_length is over the enforced throughput, only the remaining logs are returned
--  IMPORTANT: Make sure to obtain a lock before calling this method.
function AsyncLogger:getLogsFromSharedDict()
    -- convert shared_dict to table
    local allMetrics = self.logerSharedDict
    if (allMetrics == nil) then
        return nil
    end

    local logs = {}
    local logs_c = 0

    local current_throughput = self.logerSharedDict:get("throughput_counter")
    current_throughput = current_throughput or 0
    local actual_flush_length = self.flush_length
    if (actual_flush_length + current_throughput >= self.flush_throughput) then
        actual_flush_length = self.flush_throughput - current_throughput
    end
    -- actual_flust_length should never be 0.
    -- 0 means get ALL records from the dictionary which is very bad
    if (actual_flush_length <= 0) then
        -- at this point we might be over the expected throughput
        return logs, logs_c
    end

    local keys = allMetrics:get_keys(actual_flush_length)
    local dict_counter = self:getCount()

    for i, metric in pairs(keys) do
        -- make sure to exclude any other variables stored in this dict which are not actually logs
        -- an alternative would be to use another dictionary but it would make the API for the user a little more complex
        if (metric ~= "counter"
                and metric ~= "pending_threads"
                and metric ~= "running_threads"
                and metric ~= "pendingTimers_lock"
                and metric ~= "flush_lock"
                and metric ~= "lastFlushTimestamp"
                and metric ~= "throughput_counter") then
            local v = allMetrics:get(metric)
            if (v ~= nil and metric ~= nil) then
                logs[metric] = v
                logs_c = logs_c + 1
            end
            allMetrics:delete(metric)
        end
    end

    ngx.log(ngx.DEBUG, "pending_threads=", tostring(self:get_pending_threads()),
        ", running_threads=", tostring(self:get_running_threads()),
        ", counter=", tostring(dict_counter),
        ", logs_c=", tostring(logs_c),
        ", actual_flush_length=", tostring(actual_flush_length)
    )

    local remaining_logs = dict_counter - logs_c
    if (remaining_logs < 0) then
        ngx.log(ngx.DEBUG, "Unexpected value for remaining logs:", tostring(remaining_logs))
        remaining_logs = 0
    end
    if (actual_flush_length > logs_c) then
        -- if the number of elements returned by the dictionary is less than the expected length
        -- there are no more remaining logs left so we are safe to reset the counter to 0 as well
        ngx.log(ngx.DEBUG, "Correcting the 'counter' for the logs to 0.")
        remaining_logs = 0
    end
    self.logerSharedDict:set("counter", remaining_logs)
    if (logs_c > 0) then
        self.logerSharedDict:incr("throughput_counter", logs_c)
    end
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
    -- #######  get a MUTEX lock
    local flush_lock = lock_cls:new(self.sharedDict, {exptime = 0.100, timeout=0.900})
    local elapsed, err = flush_lock:lock("flush_lock")
    if (err) then
        ngx.log(ngx.ERR, "Could not acquire lock for 'flush_lock'. premature=", tostring(premature), ", err=", err)
    end
    ngx.log(ngx.DEBUG, "Lock 'flush_lock' acquired in:", tostring(elapsed), " seconds.")

    -- read the data and expire logs
    local ok, logs, number_of_logs = pcall(self.getLogsFromSharedDict, self)
    if (not ok) then
        ngx.log(ngx.ERR, "Could not read logs from shared dict. err:", tostring(logs))
    end

    -- ######  release the MUTEX lock
    local unlock_ok, err = flush_lock:unlock()
    if (not unlock_ok) then
        ngx.log(ngx.ERR, "Could not unlock 'flush_lock':", err)
    end

    if (number_of_logs > 0) then
        -- call the backend
        local ok, responseCode, headers, status, body, failedRecords = self.backendInst:sendLogs(logs)

        -- Handling failure cases
        -- 1. Check if the backend responded OK
        if (responseCode ~= 200 and failedRecords == nil) then
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

        if (self.callback ~= nil) then
            local ok, resp = pcall(self.callback, {
                logs_sent = number_of_logs,
                logs_failed = logsToResendCounter,
                backend_response_code = responseCode,
                threads_running = self:get_running_threads(),
                threads_pending = self:get_pending_threads(),
                buffer_length = self:getCount()
            })
            if (not ok) then
                ngx.log(ngx.ERR, "callback error.")
            end
        end
        return
    end
    ngx.log(ngx.WARN, "Could not flush metrics to backend ", tostring(self.backend) , " number_of_logs=", tostring(number_of_logs) )
end

local function flushMetrics_timerCallback(premature, self)
    ngx.log(ngx.DEBUG, "Flushing metrics with premature flag:", premature, " to backend:", tostring(self.backend), " self=", tostring(tableToString(self)) )

    -- decremenet the number of pending threads before flushing
    self.logerSharedDict:incr("pending_threads", -1)
    -- increment the number of running threads
    self.logerSharedDict:incr("running_threads", 1)

    local ok, result = pcall(doFlushMetrics, premature, self)

    -- decrement the number of running threads
    self.logerSharedDict:incr("running_threads", -1)
    -- save a timestamp of the last flush
    self.logerSharedDict:set("lastFlushTimestamp", ngx.now())
end

function AsyncLogger:get_pending_threads()
    local pending_threads = tonumber(self.logerSharedDict:get("pending_threads"))
    if (pending_threads == nil or pending_threads < 0) then
        pending_threads = 0
        self.logerSharedDict:add("pending_threads", 0)
    end
    return pending_threads
end

function AsyncLogger:get_running_threads()
    local running_threads = tonumber(self.logerSharedDict:get("running_threads"))
    if (running_threads == nil or running_threads < 0) then
        running_threads = 0
        self.logerSharedDict:add("running_threads", 0)
    end
    return running_threads
end

-- Send data to a backend.
function AsyncLogger:flushMetrics()
    local pending_threads = self:get_pending_threads()
    local running_threads = self:get_running_threads()

    if (pending_threads + running_threads <= self.flush_concurrency) then
        -- pick a random delay between 10ms to 100ms when to spawn this timer
        local delay = math.random(10, 100)
        local ok, err = ngx.timer.at(delay / 1000, flushMetrics_timerCallback, self)
        if not ok then
            ngx.log(ngx.WARN, "Could not flushMetrics this time, will retry later. Details: ", err)
            return false
        end
        ngx.log(ngx.DEBUG, "Scheduling flushMetrics in " .. tostring(delay) .. "ms.")
        -- at this point we're certain the timer has started successfully
        self.logerSharedDict:incr("pending_threads", 1)
        return true
    end
    -- concurrency limit is reached at this point, no more thread is spawn
    return false
end


return AsyncLogger