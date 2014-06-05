--
-- Created by IntelliJ IDEA.
-- User: ddascal
-- Date: 30/05/14
-- Time: 16:00
-- To change this template use File | Settings | File Templates.
--

local http = require "api-gateway.logger.http"
local HttpLogger = require "api-gateway.logger.backend.HttpLogger"
local AWSV4S = require "api-gateway.aws.AwsV4Signature"

local AwsSnsLogger = HttpLogger:new()

function AwsSnsLogger:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if ( o ~= nil) then
        self.aws_region = o.aws_region
        self.sns_topic_arn = o.sns_topic_arn
    end
    return o
end

function AwsSnsLogger:sendLogs(logs_table)
    local hc = http:new()

    local request_body = self:getRequestBody(logs_table)
    ngx.log(ngx.WARN, "[HttpLogger] Request BODY:" .. request_body .. "!"  )


    local ok, code, headers, status, body  = hc:request {
        url = "/sns-logger",
        host = "sns" .. "." .. self.aws_region .. ".amazonaws.com",
        body = request_body,
        method = "POST",
        headers = self:getRequestHeaders(request_body)
    }
    ngx.log(ngx.WARN, "[HttpLogger] RESPONSE BODY:" .. body)
    return ok, code, headers, status, body
end

local function urlEncode(inputString)
    if (inputString) then
        inputString = string.gsub (inputString, "\n", "\r\n")
        inputString = string.gsub (inputString, "([^%w %-%_%.%~])",
            function (c) return string.format ("%%%02X", string.byte(c)) end)
        inputString = string.gsub (inputString, " ", "+")
    end
    return inputString
end

function AwsSnsLogger:getRequestBody(logs_table)
    local r = ""
    for key,value in pairs(logs_table) do
        if(key ~= "counter") then
            r  = r .. "," .. value
        end
    end
    --remove the first "," from r
    r = string.sub(r, 2)

    -- Get the security credentials to make use of for sns logging
    getSecurityCredentials()

    local requestbody = "Action=Publish&Subject=AwsSnsLogger&TopicArn=" .. self.sns_topic_arn .. "&Message=" .. r

    local securitytoken  = urlEncode("AQoDYXdzEGYa0AOg6LJSakr+8JW3XfWfHffABrGc112YT31QKMpOz+OAzaaEsDPQvYrZACeSvWO6cl6Xw/cZ8v/D4guzL+TgsxHDAyr/PximPrtyRPb7vRXiDhTYmz5POdbacI1YRPL8idFw0CLMvFG2stA7BYEcEI7IErUwMktwXsOBYsmSTt+QJnDxPF9zm5dp50CPOzdnqV72innxdeUGsBsgqI97vl16hybzUb0RkGUGDXi/8qnvmY0n0izHAyb4X5qLdnNn1DNjGlHM048ikexQWmaBIbFAHu4gsFf1YAuoT4JYxupsQv7PCXTa3t+vQd4Rut67wZnXz+Fnn05RT0ztPJXLZukEOzoYU7erttxZDASGiQu6qDnmiwSgu1LXoaG2zsTM5OJBDJscQmD5KaZeNWsWbiEBC3ZPtXrnN8sNfnRi+3WMIELNcrSzcWI4DFOP6LmNm4/jSS2spBQkkEOzF83IJyxcQhj9k9yqVHjfnl94C8nSLDrsZYye6D4vOsTCma3AF0cJ4ouNwfqme3E+3blMjIGm5TXFBCJoPKGm4BSfzYFfiEX/gBcuvb7KP+xZ6llq0JAUHL9c+sjP0bUtHu7JZDNoqLdVEAWuHPfvHpmlXNbo/yDRkb6cBQ==")

    requestbody = requestbody .. "&SecurityToken=" .. securitytoken

    return requestbody
end

function AwsSnsLogger:getRequestHeaders(request_body)

    local awsAuth =  AWSV4S:new({
        aws_region  = self.aws_region,
        aws_service = "sns",
        aws_secret_key = self.aws_secret_key,
        aws_access_key = self.aws_access_key
    })

    local method = "POST"
    local url = "/sns-logger"
    local uri_args = {}

    local authorization = awsAuth:getAuthorizationHeader(
        method,
        url,
        uri_args, -- TODO: support uri args table for GET
        request_body
    )

    return {
        Authorization = authorization,
        ["X-Amz-Date"] = awsAuth.aws_date,
        ["Content-Type"] = "application/x-www-form-urlencoded"
    }

end

return AwsSnsLogger

