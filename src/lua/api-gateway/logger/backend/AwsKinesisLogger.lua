---
-- A simple Kinesis logging class that takes a list of key,value pairs and sends them to Kinesis using "putRecords" action.
--


local _M = {}

function _M:new(o)
    o = o or {}

    if (not o.___super ) then
        self:constructor(o)
    end

    setmetatable(o, self)
    self.__index = self
    return o
end

function _M:constructor(o)
    --1. TODO initialize  Kinesis Service
end

function _M:sendLogs(logs_table)
    local records = self:getKinesisRecords(logs_table)
    -- TODO: send the kinesis message using the Kinesis Service
end

function _M:getKinesisRecords(logs_table)
end

return _M
