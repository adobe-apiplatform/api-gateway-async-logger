local crypto = require 'crypto'

a = ngx.var.args
ts = {}
ks = {}
es = {}

function kv(s)
  local l
  if #s == 0 then return end
  l = string.find(s, '=', 1, true)
  if l == nil then
    return s, ''
  else
    return string.sub(s, 1, l - 1), string.sub(s, l + 1)
  end
end

-- unreserved characters are unchanged, others % encoded.
-- http://docs.amazonwebservices.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/index.html?Query_QueryAuth.html
-- A-Z, a-z, 0-9, hyphen ( - ), underscore ( _ ), period ( . ), and tilde ( ~ ).

-- note we do not re-urlencode inbound data, as nginx does not decode, so this should be encoded using these same rules to pass signature

function psub(c)
  return '%' .. string.format('%2X', string.byte(c, 1))
end

function urlencode(s)
  return string.gsub(s, '[^a-zA-Z0-9%-_%.~]', psub)
end

function extra(k, v)
  local uv = urlencode(v)
  es[k] = uv
  if ts[k] == nil then
    ts[k] = uv
    table.insert(ks, k)
  end
end

local utc = ngx.utctime()
local now = string.sub(utc, 1, 10) .. 'T' .. string.sub(utc, 12) .. 'Z'

ll = 0
local l, s, k, v

while true do
  l = string.find(a, '&', ll, true)
  if l ~= nil then
    s = string.sub(a, ll, l - 1)
  else
    s = string.sub(a, ll)
  end
  k, v = kv(s)
  if k then
    ts[k] = v
    table.insert(ks, k)
  end
  if l == nil then break end
  ll = l + 1
end

extra('X-Amz-Date', now)
--extra('Timestamp', now)
--extra('Version', '2012-10-17')
extra('SignatureMethod', 'HmacSHA256')
extra('SignatureVersion', '4')
extra('AWSAccessKeyId', ngx.var.aws_access_key)
-- extra('DomainName', ngx.var.domain)

table.sort(ks)

for k, v in pairs(ks) do
  ks[k] = v .. '=' .. ts[v]
end

string_to_sign = 'GET\nsns.us-east-1.amazonaws.com\n/\n' .. table.concat(ks, '&')

signature = ngx.encode_base64(crypto.hmac.digest('sha256', string_to_sign, ngx.var.aws_secret_key, true))

-- note we return additional query string, as nginx rewrite leaves original parameters

ee = {}
for k, v in pairs(es) do
  table.insert(ee, k .. '=' .. v)
end

query = table.concat(ee, '&') .. '&Signature=' .. urlencode(signature)

return query