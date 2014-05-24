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
    local host = "https://".. aws_service .. "." .. aws_region .. ".amazonaws.com/"
    local subject = "analytics"
    local sns_topic_arn = ngx.var.analytics_topic_arn or "arn:aws:sns:us-east-1:492299007544:apiplatform-dev-ue1-topic-analytics"

    local request_uri = "/"

    local request_method = "POST"

      -- get the data from shared dict
    local BufferedAsyncLogger = require "logger.BufferedAsyncLogger"
    local logger = BufferedAsyncLogger:new({
        flush_length = 2,
        sharedDict = "stats_all",
        flushDestination = "/flush-metrics"
    })
    local req_body = logger:getDataFromSharedDict()


    -- calculate the auth header for posting to aws
    local AWSV4S = require "aws.AwsV4Signature"
    local awsAuth =  AWSV4S:new( {
        aws_region  = ngx.var.aws_region,
        aws_service = ngx.var.aws_service
    })
    local authHeader = awsAuth:getAuthorizationHeader(
        ngx.var.request_method,
        request_uri,
        ngx.req.get_uri_args(),
        subject,
        req_body
    )
    ngx.log(ngx.INFO, "------authHeader---------")
    ngx.log(ngx.INFO, authHeader)
    ngx.log(ngx.INFO, "-------authHeader--------")

    local tcp = ngx.socket.tcp
    local sock = tcp()
    sock:settimeout(100000)

    ok, err = sock:connect(host,80)
    if err then
        ngx.log(ngx.ERR, "error in connecting to socket" .. err)
    end

    local uri = "/?Action=Publish&Message=" .. "hello_from_nginx" .. "&Subject=" .. "nginx" .. "&TopicArn=" .. topicarn

    local reqline = "POST "  .. uri .. " HTTP/1.1" .. "\\r\\n"


    local headers = "Content-Type" .. ":" .. "application/x-www-form-urlencoded; charset=utf-8" .."\\r\\n" ..
            "X-Amz-Date" .. ":" .. ngx.var.x_amz_date .."\\r\\n" ..
            "Authorization" .. ":" .. authorization .."\\r\\n" ..
            "Content-Length" .. ":" .. "15" .. "\\r\\n"

    bytes, err = sock:send(reqline .. headers)
    if err then
        ngx.log(ngx.ERR, "error in sending header to socket" .. err)
        sock:close()
        return nil, err
    end
    ngx.say("------------")
    ngx.say(bytes)
    ngx.say("------------")

    local body = "Action=Publish&Message=" .. message .. "&Subject=" .. subject .. "&TopicArn=" .. topicarn

    bytes, err = sock:send(jsonbody)
    if err then
        ngx.log(ngx.ERR, "error in sending body to socket" .. err)
        sock:close()
        return nil, err
    end
    ngx.say("------------")
    ngx.say(bytes)
    ngx.say("------------")

    local status_reader = sock:receiveuntil("\\r\\n")

    local data, err, partial = status_reader()
    if not data then
        return nil, "read status line failed " .. err
    end

    local t1, t2, code = string.find(data, "HTTP/%d*%.%d* (%d%d%d)")

    ngx.say(tonumber(code), data)

end

return PostLogs