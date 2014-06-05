--
-- Created by IntelliJ IDEA.
-- User: nramaswa
-- Date: 6/4/14
-- Time: 5:03 PM
-- To change this template use File | Settings | File Templates.
--

local cjson = require "cjson"

local AWSIAMCredentials

function AWSIAMCredentials:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if ( o ~= nil) then
        self.loggerSharedDict = ngx.shared[o.sharedDict]
    end
    return o
end


local function fetchSecurityCredentialsFromAWS(loggerDict)
    local iam_end_point ="169.254.169.254/latest/meta-data/iam/security-credentials/"
    local iamUserName = "apiplatform-web"
    local credentialValidFor = 3600 -- in seconds
    local iamHost = iam_end_point .. iamUserName.. "&DurationSeconds=" .. credentialValidFor

    -- expire the keys in the shared dict 6 seconds before the aws keys expire
    local expire_at = credentialValidFor - 6
    local hc1 = http:new()

    local sample_body = "{ \"Code\" : \"Success\",\"LastUpdated\" : \"2014-06-04T20:59:45Z\",\"Type\" : \"AWS-HMAC\",\"AccessKeyId\" : \"ASIAIT6QKA53TLHC72EA\"," ..
            " \"SecretAccessKey\" : \"L8MJ1OcStvq79FEsEfv9mR8qvz5yURwxlPYmg76H\", "..
            "\"Token\" : \"AQoDYXdzEGYa0AOg6LJSakr+8JW3XfWfHffABrGc112YT31QKMpOz+OAzaaEsDPQvYrZACeSvWO6cl6Xw/cZ8v/D4guzL+TgsxHDAyr/PximPrtyRPb7vRXiDhTYmz5POdbacI1YRPL8idFw0CLMvFG2stA7BYEcEI7IErUwMktwXsOBYsmSTt+QJnDxPF9zm5dp50CPOzdnqV72innxdeUGsBsgqI97vl16hybzUb0RkGUGDXi/8qnvmY0n0izHAyb4X5qLdnNn1DNjGlHM048ikexQWmaBIbFAHu4gsFf1YAuoT4JYxupsQv7PCXTa3t+vQd4Rut67wZnXz+Fnn05RT0ztPJXLZukEOzoYU7erttxZDASGiQu6qDnmiwSgu1LXoaG2zsTM5OJBDJscQmD5KaZeNWsWbiEBC3ZPtXrnN8sNfnRi+3WMIELNcrSzcWI4DFOP6LmNm4/jSS2spBQkkEOzF83IJyxcQhj9k9yqVHjfnl94C8nSLDrsZYye6D4vOsTCma3AF0cJ4ouNwfqme3E+3blMjIGm5TXFBCJoPKGm4BSfzYFfiEX/gBcuvb7KP+xZ6llq0JAUHL9c+sjP0bUtHu7JZDNoqLdVEAWuHPfvHpmlXNbo/yDRkb6cBQ==\","..
            "\"Expiration\" : \"2014-06-05T03:17:46Z\" }"

    local ok, code, headers, status, body  = hc1:request {
        host = iamHost,
        method = "GET"
    }
    body = body or sample_body

    local aws_response = cjson.decode(body)

    if(aws_response["Code"] == "Success") then
        ngx.log(ngx.WARN, "[AWSRequest] Logging credentials:" .. body)

        -- set the values and the expiry time
        loggerDict:set("AccessKeyId", aws_response["AccessKeyId"],expire_at)
        loggerDict:set("SecretAccessKey",  aws_response["SecretAccessKey"],expire_at)
        local token = urlEncode(aws_response["Token"])
        loggerDict:set("Token",token,expire_at)
    end

    return ok
end

function AWSIAMCredentials:updateSecurityCredentials()
    getSecurityCredentials(self.loggerSharedDict)

end

function AWSIAMCredentials:getSecurityCredentials()
    local accessKeyId = self.loggerSharedDict:get("AccessKeyId")
    local secretAccessKey = self.loggerSharedDict:get("AccessKeyId")
    local token = self.loggerSharedDict:get("AccessKeyId")

    if(accessKeyId == nil) then
        self:updateSecurityCredentials()
    end
end

return AWSIAMCredentials
