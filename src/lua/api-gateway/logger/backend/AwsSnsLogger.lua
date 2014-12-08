--
-- Created by IntelliJ IDEA.
-- User: ddascal
-- Date: 30/05/14
-- Time: 16:00
-- To change this template use File | Settings | File Templates.
--

local http = require"api-gateway.logger.http"
local HttpLogger = require"api-gateway.logger.backend.HttpLogger"
local AWSV4S = require"api-gateway.aws.AwsV4Signature"
local AWSIAMCredentials = require"api-gateway.aws.AWSIAMCredentials"
local SnsService = require"api-gateway.aws.sns.SnsService"
local url = require"api-gateway.logger.url"

local snsService

local AwsSnsLogger = {}

function AwsSnsLogger:new(o)
    o = o or {}

    if (not o.___super ) then
        self:constructor(o)
    end

    setmetatable(o, self)
    self.__index = self
    return o
end

function AwsSnsLogger:constructor(o)
    ngx.log(ngx.DEBUG, "constructor")

    self.aws_region = o.aws_region
    self.sns_topic_arn = o.sns_topic_arn
    self.aws_secret_key = o.aws_secret_key
    self.aws_access_key = o.aws_access_key
    self.aws_iam_user = o.aws_iam_user

    local iam_user = o.aws_iam_user

    local snsServiceConfig = {
        aws_region = o.aws_region,
        aws_secret_key = o.aws_secret_key,
        aws_access_key = o.aws_access_key,
        aws_debug = true, -- print warn level messages on the nginx logs
        aws_conn_keepalive = 60000, -- how long to keep the sockets used for AWS alive
        aws_conn_pool = 100 -- the connection pool size for sockets used to connect to AWS
    }

    if ( iam_user ~= nil ) then
        snsServiceConfig.aws_iam_user = iam_user.iam_user
        snsServiceConfig.security_credentials_host = iam_user.security_credentials_host
        snsServiceConfig.security_credentials_port = iam_user.security_credentials_port
        snsServiceConfig.shared_cache_dict = iam_user.shared_cache_dict
    end

    snsService = SnsService:new(snsServiceConfig)
end

function AwsSnsLogger:sendLogs(logs_table, retryFlag)
    local shouldRetry = retryFlag or false

    local subject = "AwsSnsLogger"
    local msg = self:getSnsMessage(logs_table)

    local response, code, headers, status, body = snsService:publish(subject, msg, self.sns_topic_arn)

    if (response ~= nil and response.PublishResponse ~= nil and response.PublishResponse.PublishResult ~= nil) then
        local messageId = tostring(response.PublishResponse.PublishResult.MessageId)
        ngx.log(ngx.DEBUG, "Log has been published to SNS. MessageId:", messageId)
    end

    return response, code, headers, status, body
end

function AwsSnsLogger:getSnsMessage(logs_table)
    local r = ""
    for key, value in pairs(logs_table) do
        if (key ~= "counter") then
            r = r .. "," .. value
        end
    end
    --remove the first "," from r
    r = string.sub(r, 2)
    return r
end

return AwsSnsLogger

