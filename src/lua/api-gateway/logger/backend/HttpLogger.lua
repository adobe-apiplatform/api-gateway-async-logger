--
-- Created by IntelliJ IDEA.
-- User: ddascal
-- Date: 30/05/14
-- Time: 15:58
-- To change this template use File | Settings | File Templates.
--
local http = require "api-gateway.logger.http"

local HttpLogger = {}

local DEFAULT_METHOD = "POST"
local DEFAULT_HOST = "localhost"

function HttpLogger:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    self.method = DEFAULT_METHOD
    self.host = DEFAULT_HOST
    if ( o ~= nil) then
        self.url = o.url
        self.host = o.host
        self.method = o.method
        self.port = o.port
    end

    return o
end

function HttpLogger:sendLogs(logs_table)
    local hc = http:new()

    local request_body = self:getRequestBody(logs_table)
    --ngx.log(ngx.WARN, "HttpLogger BODY" .. request_body .. "!"  )

    local ok, code, headers, status, body  = hc:request {
        url = self.url,
        host = self.host,
        port = self.port,
        body = request_body,
        method = self.method,
        headers = self:getRequestHeaders()
    }
    ngx.log(ngx.DEBUG, "RESPONSE BODY:" .. body)
    return ok, code, headers, status, body
end

function HttpLogger:getRequestBody(logs_table)
    local r = ""
    for key,value in pairs(logs_table) do
        if(key ~= "counter") then
            r  = r .. "," .. value
        end
    end
    --remove the first "," from r
    r = string.sub(r, 2)

    return r
end

function HttpLogger:getRequestHeaders()
    return {}
end

return HttpLogger

