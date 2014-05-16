--
-- Created by IntelliJ IDEA.
-- User: ddascal
-- Date: 15/05/14
-- Time: 15:09
--
-- Implements the new Version 4 HMAC authorization.
--
local resty_sha256 = require "resty.sha256"
local resty_sha1 = require "resty.sha1"
local str = require "resty.string"
-- Manual: http://mkottman.github.io/luacrypto/manual.html
local crypto = require 'crypto'

local HmacAuthV4Handler = {}

function HmacAuthV4Handler:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if ( o ~= nil) then
        self.service_name = o.service_name
        self.region_name = o.region_name
    end
    return o
end

local function _sign_sha256(key, msg, raw)
    local binary_format = raw or false
    local digest = crypto.hmac.digest('sha256', msg, key, binary_format)
    return digest
end


local function _sha256_hex(msg)
    return crypto.digest("sha256", msg)
end

local _sign = _sign_sha256
local _hash = _sha256_hex

local function get_hashed_canonical_request(method, uri, querystring, headers, requestPayload, date)
    local sss = "POST\n" ..
                 "/test-signature\n" ..
                 "Action=Publish&Message=hello_from_nginx&TopicArn=arn%3Aaws%3Asns%3Aus-east-1%3A492299007544%3Aapiplatform-dev-ue1-topic-analytics\n" ..
                 "host:sns.us-east-1.amazonaws.com\n" ..
                 "x-amz-date:" .. date .. "\n" ..
                 "\n" ..
                 "host;x-amz-date\n" ..
                 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    ngx.log(ngx.WARN, "Canonical String to Sign is:\n" .. sss)

    local digest = crypto.digest("sha256", sss)

    ngx.log(ngx.WARN, "Canonical String DIGEST is:\n" .. digest)

    return digest
end

local function get_hashed_canonical_request2(method, uri, querystring, headers, requestPayload)
    local hash = method .. '\n' ..
                 uri .. '\n' ..
                (querystring or "") .. '\n'
    -- add canonicalHeaders
    local canonicalHeaders = ""
    local signedHeaders = ""
    for h_n,h_v in pairs(headers) do
        -- todo: trim and lowercase
        canonicalHeaders = canonicalHeaders .. h_n .. ":" .. h_v .. "\n"
        signedHeaders = signedHeaders .. h_n .. ";"
    end
    --remove the last ";" from the signedHeaders
    signedHeaders = string.sub(signedHeaders, 1, -2)

    hash = hash .. canonicalHeaders .. "\n" .. signedHeaders .. "\n"

    hash = hash .. _hash(requestPayload or "")

    ngx.log(ngx.WARN, "Canonical String to Sign is:\n" .. hash)

    local final_hash = _hash(hash)
    ngx.log(ngx.WARN, "Canonical String HASHED is:\n" .. final_hash .. "\n")
    return final_hash
end

local function get_string_to_sign(algorithm, request_date, credential_scope, hashed_canonical_request)
    local s = algorithm .. "\n" .. request_date .. "\n" .. credential_scope .. "\n" .. hashed_canonical_request
    ngx.log(ngx.WARN, "String-to-Sign is:\n" .. s)
    return s
end

local function get_derived_signing_key(aws_secret_key, date, region, service )
    local kDate = _sign("AWS4" .. aws_secret_key, date, true )
    local kRegion = _sign(kDate, region, true)
    local kService = _sign(kRegion, service, true)
    local kSigning = _sign(kService, "aws4_request", true)

    return kSigning
end

local function getSignature()
    local aws_secret = ngx.var.aws_secret_key
    local utc = ngx.utctime()
    local date1 = string.gsub(string.sub(utc, 1, 10),"-","")
    local date2 = date1 .. 'T' .. string.gsub(string.sub(utc, 12),":","") .. 'Z'
    ngx.var.x_amz_date = date2
    ngx.var.x_amz_date_short = date1
    local headers = {}
    headers.host = "sns.us-east-1.amazonaws.com"
    headers["x-amz-date"] = date2
    --headers["content-type"] = "application/x-www-form-urlencoded; charset=utf-8"
    --headers["content-length"] = 0
    local sign = _sign( get_derived_signing_key( aws_secret,
                                             date1,
                                             "us-east-1",
                                             "sns"),
                    get_string_to_sign("AWS4-HMAC-SHA256",
                                        date2,
                                        date1 .. "/us-east-1/sns/aws4_request",
                                        get_hashed_canonical_request("POST", "/", "Action=Publish&Message=hello_from_nginx&TopicArn=arn%3Aaws%3Asns%3Aus-east-1%3A492299007544%3Aapiplatform-dev-ue1-topic-analytics", headers, "", date2) ) )
    return sign
end


return getSignature()








