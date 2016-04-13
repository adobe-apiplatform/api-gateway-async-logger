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

---
-- A simple Kinesis logging class that takes a list of key,value pairs and sends them to Kinesis using "putRecords" action.
--
--
local KinesisService = require "api-gateway.aws.kinesis.KinesisService"
local cjson = require "cjson"

local kinesisService

local _M = {}

function _M:new(o)
    o = o or {}

    if (not o.___super) then
        self:constructor(o)
    end

    setmetatable(o, self)
    self.__index = self
    return o
end

function _M:constructor(o)
    ngx.log(ngx.DEBUG, "constructor")

    assert(o.kinesis_stream_name ~= nil, "Please provide a valid kinesis_stream_name in the init object.")

    self.aws_region = o.aws_region
    self.kinesis_stream_name = o.kinesis_stream_name
    self.aws_secret_key = o.aws_secret_key
    self.aws_access_key = o.aws_access_key
    self.aws_iam_user = o.aws_iam_user

    local kinesisServiceConfig = {
        aws_region = o.aws_region,
        aws_credentials = o.aws_credentials, -- credentials provider
        aws_secret_key = o.aws_secret_key, -- deprecated but kept for backwards compatibility
        aws_access_key = o.aws_access_key, -- deprecated but kept for backwards compatibility
        aws_debug = o.aws_debug, -- print warn level messages on the nginx logs
        aws_conn_keepalive = o.aws_conn_keepalive, -- how long to keep the sockets used for AWS alive
        aws_conn_pool = o.aws_conn_pool -- the connection pool size for sockets used to connect to AWS
    }

    kinesisService = KinesisService:new(kinesisServiceConfig)
end

function _M:sendLogs(logs_table)
    local records, rcount = self:getKinesisRecords(logs_table)
    ngx.log(ngx.DEBUG, "sending ", tostring(rcount), " logs to kinesis.")
    local response, code, headers, status, body = kinesisService:putRecords(self.kinesis_stream_name, records)

    local failedRecords

    if (response ~= nil) then
        ngx.log(ngx.DEBUG, "Logs have been sent to Kinesis. FailedRecordCount:", tostring(response.FailedRecordCount))

        if ( response.FailedRecordCount > 0 ) then
            --local b = ngx.re.gsub(tostring(body), "com\.amazonaws\.kinesis\.v20131202\.[^\s]+,", "", "ijo")
            ngx.log(ngx.WARN, "Some logs were not sent to Kinesis. FailedRecordCount:", tostring(response.FailedRecordCount))
            -- response.Records may be an array with elements like
            -- [{"ErrorCode":"ProvisionedThroughputExceededException","ErrorMessage":"Rate exceeded for shard shardId-000000000"},{..}, ...]
            -- ASSUMPTION: the index of the failed record matches the index in the paylod sent to Kinesis
            local partitionKey
            local recordData
            failedRecords = {}
            for i, kinesisRecordResponse in ipairs(response.Records) do
                if (kinesisRecordResponse ~= nil and kinesisRecordResponse.ErrorCode ~= nil
                        and records ~= nil and records[i] ~= nil) then
                    -- records need to be base64 decoded
                    partitionKey = records[i].PartitionKey
                    recordData = ngx.decode_base64(tostring(records[i].Data))
                    failedRecords[partitionKey] = recordData
                end
            end

            if (body ~= nil) then
                local b, n , err = ngx.re.gsub(body, "com\\.amazonaws\\.kinesis\\.v20131202\\.[^\\s]+,", "", "ijo")
                b, n , err = ngx.re.gsub(b, "\"SequenceNumber[^}]+", "", "ijo")
                ngx.log(ngx.WARN, "Error on ", tostring(response.FailedRecordCount), " records.", "MORE DETAILS:", tostring(b))
            end
        end

    end

    if (code ~= 200 ) then
        ngx.log(ngx.WARN, "Logs were not sent to Kinesis. AWS Response:", tostring(code))
        if (body ~= nil) then
            local b, n , err = ngx.re.gsub(body, "com\\.amazonaws\\.kinesis\\.v20131202\\.[^\\s]+,", "", "ijo")
            ngx.log(ngx.WARN, "Error on ", tostring(rcount), " records.", "MORE DETAILS:", tostring(b))
        end
    end

    return response, code, headers, status, body, failedRecords
end

---
-- Returns a new table with an array of records to be sent to kinesis
-- records = {
--                {
--                    Data = "55555",
--                    PartitionKey = "partitionKey1"
--                },
--                {
--                    Data = "7777777",
--                    PartitionKey = "partitionKey2"
--                }
--            }
-- @param logs_table A table with key,value pairs holding the logs
--
function _M:getKinesisRecords(logs_table)
    local r = {}
    local nr = 1
    for key, value in pairs(logs_table) do
        -- exclude the counter of the number of values in the shared dict
        if (key ~= "counter") then -- TODO: this line may be removed as well
        r[nr] = {
            Data = value,
            PartitionKey = key
        }
        nr = nr + 1
        end
    end
    return r, nr
end

return _M
