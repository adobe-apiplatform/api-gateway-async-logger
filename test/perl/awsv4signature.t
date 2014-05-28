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

            resolver 10.8.4.247;

            content_by_lua '

                local host = ngx.var.aws_service .."." .. ngx.var.aws_region .. ".amazonaws.com"

                local amzdate = ngx.var.x_amz_date

                local AWSV4S = require "aws.AwsV4Signature"
                local awsAuth =  AWSV4S:new({
                                   aws_region  = ngx.var.aws_region,
                                   aws_service = ngx.var.aws_service
                              })

                local requestbody = "Action=Publish&Subject=HELLO-FROM-POST&TopicArn=arn:aws:sns:us-east-1:492299007544:apiplatform-dev-ue1-topic-analytics"

                local msg = "I MAY BE A LONG MESSAGE.YOU HAVE BEEN WARNED"
                for i=1,60000 do msg = msg .. "abcd" end

                requestbody = requestbody .. "&Message=" .. msg

                local authorization = awsAuth:getAuthorizationHeader( ngx.var.request_method,
                                                                    "/test-signature",
                                                                    {}, -- ngx.req.get_uri_args()
                                                                    requestbody)

                local http = require "logger.http"
                local hc = http:new()


                local ok, code, headers, status, body  = hc:request {
                        url = "/test-signature", -- .. "?" .. ngx.var.args,
                        host = host,
                        body = requestbody,
                        method = ngx.var.request_method,
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
            ';
        }
--- more_headers
X-Test: test
--- request
POST /test-signature?Action=Publish&Message=POST-cosocket-is-awesome&Subject=nginx-with-cosocket-and-POST-body&TopicArn=arn:aws:sns:us-east-1:492299007544:apiplatform-dev-ue1-topic-analytics
--- response_body eval
["OK"]
--- error_code: 200
--- no_error_log
[error]

