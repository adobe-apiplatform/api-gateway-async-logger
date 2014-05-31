--
-- Created by IntelliJ IDEA.
-- User: ddascal
-- Date: 30/05/14
-- Time: 16:00
-- To change this template use File | Settings | File Templates.
--


local HttpLogger = require "api-gateway.logger.backend.HttpLogger"
local AwsSnsLogger = HttpLogger:new()

function AwsSnsLogger:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    return o
end

function AwsSnsLogger:getRequestBody(logs_table)
    local r
    local value
    for i,metric in pairs(logs_table) do
        if(metric ~= "counter") then
            local value = allMetrics:get(metric)
            r  = r .. "\n" .. value
        end
    end
end

local function getAwsAuthorizationHeader()

end

function AwsSnsLogger:getRequestHeaders()
    return   {
        Authorization = getAwsAuthorizationHeader(),
        ["X-Amz-Date"] = awsAuth.aws_date,
        ["Content-Type"] = "application/x-www-form-urlencoded"
    }
end

return AwsSnsLogger

