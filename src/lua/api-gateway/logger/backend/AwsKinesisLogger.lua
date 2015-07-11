---
-- A simple Kinesis logging class that takes a list of key,value pairs and sends them to Kinesis using "putRecords" action.
--
--
local KinesisService = require "api-gateway.aws.kinesis.KinesisService"

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

    local iam_user = o.aws_iam_user

    local kinesisServiceConfig = {
        aws_region = o.aws_region,
        aws_secret_key = o.aws_secret_key,
        aws_access_key = o.aws_access_key,
        aws_debug = true, -- print warn level messages on the nginx logs
        aws_conn_keepalive = 60000, -- how long to keep the sockets used for AWS alive
        aws_conn_pool = 100 -- the connection pool size for sockets used to connect to AWS
    }

    if (iam_user ~= nil) then
        kinesisServiceConfig.aws_iam_user = iam_user.iam_user
        kinesisServiceConfig.security_credentials_host = iam_user.security_credentials_host
        kinesisServiceConfig.security_credentials_port = iam_user.security_credentials_port
        kinesisServiceConfig.shared_cache_dict = iam_user.shared_cache_dict
    end

    kinesisService = KinesisService:new(kinesisServiceConfig)
end

function _M:sendLogs(logs_table)
    local records = self:getKinesisRecords(logs_table)
    local response, code, headers, status, body = kinesisService:putRecords(self.kinesis_stream_name, records)

    if (response ~= nil) then
        ngx.log(ngx.DEBUG, "Logs have been sent to Kinesis. FailedRecordCount:", tostring(response.FailedRecordCount))
    end

    if (response ~= nil and response.FailedRecordCount > 0) then
        ngx.log(ngx.WARN, "Some logs were not sent to Kinesis. FailedRecordCount:", tostring(response.FailedRecordCount))
    end

    return response, code, headers, status, body
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
        if (key ~= "counter") then
            r[nr] = {
                Data = value,
                PartitionKey = key
            }
            nr = nr + 1
        end
    end
    return r
end

return _M
