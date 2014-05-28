# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 4) - 2;

my $pwd = cwd();

our $HttpConfig = <<_EOC_;
    # lua_package_path "$pwd/scripts/?.lua;;";
    lua_package_path 'src/lua/?.lua;;';
    lua_package_cpath 'src/lua/?.so;;';
    init_by_lua '
        local v = require "jit.v"
        v.on("$Test::Nginx::Util::ErrLogFile")
        require "resty.core"
    ';
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__


=== TEST 5: test aws s4 signature and post using tcp
--- http_config eval: $::HttpConfig
--- config
        location /test-signature {
            set $aws_access_key AKIAIBF2BKMFXSCLCR4Q;
            set $aws_secret_key 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;
            set $aws_region us-east-1;
            set $aws_service sns;
            set $aws_request_code aws4_request;
            resolver 10.8.4.247;

            set $x_amz_date '';
            set $x_amz_date_short '';

            set_by_lua $auth_signature '
                local AWSV4S = require "aws.AwsV4Signature"
                local awsAuth =  AWSV4S:new( {
                                               aws_region  = ngx.var.aws_region,
                                               aws_service = ngx.var.aws_service
                                          })
                return awsAuth:getSignature(
                                        ngx.var.request_method,
                                        "/test-signature",
                                        ngx.req.get_uri_args())
            ';


            content_by_lua '

                local host = ngx.var.aws_service .."." .. ngx.var.aws_region .. ".amazonaws.com"
                local authorization = "AWS4-HMAC-SHA256 Credential=" .. ngx.var.aws_access_key.."/" .. ngx.var.x_amz_date_short .. "/" .. ngx.var.aws_region .."/" .. ngx.var.aws_service.."/"..ngx.var.aws_request_code..",SignedHeaders=host;x-amz-date,Signature="..ngx.var.auth_signature
                local amzdate = ngx.var.x_amz_date
                local topicarn = "arn%3Aaws%3Asns%3Aus-east-1%3A492299007544%3Aapiplatform-dev-ue1-topic-analytics"
                local message = "hello_from_nginx"
                local subject ="nginx"

                local AWSV4S = require "aws.AwsV4Signature"
                local awsAuth =  AWSV4S:new()
                local jsonbody = awsAuth:formatQueryString(ngx.req.get_uri_args())

                local tcp = ngx.socket.tcp
                local sock = tcp()
                sock:settimeout(100000)

                ok, err = sock:connect(host,80)
                if err then
                    ngx.log(ngx.ERR, "error in connecting to socket" .. err)
                end

                local uri = jsonbody

                local reqline = "POST "  .. uri .. " HTTP/1.1" .. "\\r\\n"


                local headers = "Content-Type" .. ":" .. "application/x-www-form-urlencoded; charset=utf-8" .."\\r\\n" ..
                          "X-Amz-Date" .. ":" .. ngx.var.x_amz_date .."\\r\\n" ..
                          "Authorization" .. ":" .. authorization .."\\r\\n" ..
                          "Content-Length" .. ":" .. "185" .. "\\r\\n"

                bytes, err = sock:send(reqline .. headers)
                if err then
                    ngx.log(ngx.ERR, "error in sending header to socket" .. err)
                    sock:close()
                    return nil, err
                end
                ngx.say("------------")
                ngx.say(bytes)
                ngx.say("------------")

                local http = require "logger.http"
                local hc = http:new()


                local ok, code, headers, status, body  = hc:request {
                        url = host,
                        host = host,
                        method = "POST",
                        body = jsonbody,
                        headers = { Authorization = authorization,["X-Amz-Date"] = amzdate,
                        ["Content-Type"] = "application/x-www-form-urlencoded",
                        ["Content-Length"] = #jsonbody
                         },
                }
                ngx.say(ok)
                ngx.say(code)
                ngx.say(status)
                ngx.say(body)


            ';


        }
--- more_headers
X-Test: test
--- request
POST /test-signature?Action=Publish&Message=hello_from_nginx&Subject=nginx&TopicArn=arn:aws:sns:us-east-1:492299007544:apiplatform-dev-ue1-topic-analytics
--- response_body eval
["OK"]
--- error_code: 200
--- no_error_log
[error]

