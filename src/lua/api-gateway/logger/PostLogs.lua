--
-- Created by IntelliJ IDEA.
-- User: nramaswa
-- Date: 5/23/14
-- Time: 10:09 AM
-- To change this template use File | Settings | File Templates.
--


local PostLogs = {}

function PostLogs:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function PostLogs:postDataToAnalyticsSNS()

    local aws_service = ngx.var.aws_service or "sns"
    local aws_region = ngx.var.aws_region or "us-east-1"
    local host =  aws_service .. "." .. aws_region .. ".amazonaws.com"
    local subject = "analytics"
    local sns_topic_arn = ngx.var.analytics_topic_arn or "arn:aws:sns:us-east-1:492299007544:apiplatform-dev-ue1-topic-analytics"

    local request_uri = ngx.var.request_uri

    local request_method = ngx.var.request_method or "POST"

      -- get the data from shared dict
    local BufferedAsyncLogger = require "logger.BufferedAsyncLogger"
    local logger = BufferedAsyncLogger:new({
        flush_length = 20,
        sharedDict = "stats_all",
        flushDestination = "/flush-metrics"
    })
--    local req_body = logger:getDataFromSharedDict()

    local MetricsCls = require "api-gateway.core.metrics"
    local metrics = MetricsCls:new()
    local req_body = metrics:toJsonForAnalyticsSNS()

    local requestbody = "Action=Publish&Subject=".. subject .. "&TopicArn=" .. sns_topic_arn

    requestbody = requestbody .. "&Message=" .. req_body
    ngx.log(ngx.INFO, "requestbody ********* \\n " .. requestbody .. "\\n ********* \\n")


    -- calculate the auth header for posting to aws
    local AWSV4S = require "aws.AwsV4Signature"
    local awsAuth =  AWSV4S:new({
        aws_region  = ngx.var.aws_region,
        aws_service = ngx.var.aws_service
    })

    local authorization = awsAuth:getAuthorizationHeader( request_method,
        request_uri,
        ngx.req.get_uri_args(),
        requestbody
    )
    ngx.log(ngx.INFO, "request_method,request_uri, get_uri_args ********* \\n " .. request_method .."++++".. request_uri .."++++".. tostring(ngx.req.get_uri_args()).."\\n ********* \\n")

    local http = require "logger.http"
    local hc = http:new()

    ngx.log(ngx.INFO, "host, ********* \\n " .. host .. "\\n ********* \\n")

    local ok, code, headers, status, body  = hc:request {
        url = request_uri,
        host = host,
        body = requestbody,
        method = request_method,
        headers = {
            Authorization = authorization,
            ["X-Amz-Date"] = awsAuth.aws_date,
            ["Content-Type"] = "application/x-www-form-urlencoded"
        }
    }
    ngx.say(ok)
    ngx.say(code)
    ngx.say(status)
    ngx.say(body)


end


function PostLogs:postDataToInternalLocation(location)
    ngx.say("Do we need this function?")
end

return PostLogs