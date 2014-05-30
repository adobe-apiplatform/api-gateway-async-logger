# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(1);

plan tests => repeat_each() * (blocks() * 4) - 1;

my $pwd = cwd();

our $HttpConfig = <<_EOC_;
    # lua_package_path "$pwd/scripts/?.lua;;";
    lua_shared_dict stats_all 20m;
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

 === TEST 1: log data to logger
--- http_config eval: $::HttpConfig
--- config
        location /log-metrics {
                set $x_amz_date '';
                set $x_amz_date_short '';

                set $aws_access_key AKIAIBF2BKMFXSCLCR4Q;
                set $aws_secret_key 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;
                set $aws_region us-east-1;
                set $aws_service sns;
                set $aws_request_code aws4_request;
                content_by_lua '

                    local randomSeed = string.gsub(tostring(ngx.now()),"%.","")
                    local key = ngx.utctime() .."-".. math.random(randomSeed)

                    local allMetricValues = "\'publisherVal\',".."\'consumerVal\',".."\'applicationVal\',".."\'serviceVal\',".."\'region\',".."\'requestMethod\',".."\'status\',".. "\'guid\',"..
                                               "\'guid\',".."\'timstamp\',".."\'ipAddress\',".."\'requestPath\'"

                    local BufferedAsyncLogger = require "logger.BufferedAsyncLogger"
                    local logger = BufferedAsyncLogger:new({
                        flush_length = 20,
                        sharedDict = "stats_all",
                        flushDestination = "/flush-metrics"
                    })
                    logger:logMetrics(key, allMetricValues)
                    ngx.print("OK")
                ';
        }
        location /log-metrics1 {
                set $x_amz_date '';
                set $x_amz_date_short '';

                set $aws_access_key AKIAIBF2BKMFXSCLCR4Q;
                set $aws_secret_key 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;
                set $aws_region us-east-1;
                set $aws_service sns;
                set $aws_request_code aws4_request;
                content_by_lua '

                    local randomSeed = string.gsub(tostring(ngx.now()),"%.","")
                    local key = ngx.utctime() .."-".. math.random(randomSeed)

                    local allMetricValues = "\'publisherVal1\',".."\'consumerVal1\',".."\'applicationVal1\',".."\'serviceVal1\',".."\'region\',".."\'requestMethod\',".."\'status\',".. "\'guid\',"..
                                                    "\'guid\',".."\'timstamp\',".."\'ipAddress\',".."\'requestPath\'"

                    local BufferedAsyncLogger = require "logger.BufferedAsyncLogger"
                    local logger = BufferedAsyncLogger:new({
                        flush_length = 20,
                        sharedDict = "stats_all",
                        flushDestination = "/flush-metrics"
                    })
                    logger:logMetrics(key, allMetricValues)

                    local req_body = logger:getDataFromSharedDict()

                ';
        }
--- pipelined_requests eval
[
"GET /log-metrics",
"GET /log-metrics1"
]
--- response_body_like eval
["OK",
" {\"headings\":['publisher','consumer','application','service','region','requestMethod','status','guid','guid','timstamp','ipAddress','requestPath'],\"values\":[['publisherVal','consumerVal','applicationVal','serviceVal','region','requestMethod','status','guid','guid','timstamp','ipAddress','requestPath'],['publisherVal1','consumerVal1','applicationVal1','serviceVal1','region','requestMethod','status','guid','guid','timstamp','ipAddress','requestPath']]} "
]
--- error_code_like eval
[200,200]
--- no_error_log
[error]


=== TEST 2:  flush some data to sns
--- http_config eval: $::HttpConfig
--- config
        location /log-metrics {
                set $aws_access_key AKIAIBF2BKMFXSCLCR4Q;
                set $aws_secret_key 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;
                set $aws_region us-east-1;
                set $aws_service sns;

                resolver 10.8.4.247;

                content_by_lua '
                    local randomSeed = string.gsub(tostring(ngx.now()),"%.","")
                    local key = ngx.utctime() .."-".. math.random(randomSeed)

                    local allMetricValues = "\'publisherVal1\',".."\'consumerVal1\',".."\'applicationVal1\',".."\'serviceVal1\',".."\'region\',".."\'requestMethod\',".."\'status\',".. "\'guid\',"..
                                                    "\'guid\',".."\'timstamp\',".."\'ipAddress\',".."\'requestPath\'"

                    local BufferedAsyncLogger = require "logger.BufferedAsyncLogger"
                    local logger = BufferedAsyncLogger:new({
                        flush_length = 20,
                        sharedDict = "stats_all",
                        flushDestination = "/flush-metrics"
                    })
                    logger:logMetrics(key, allMetricValues)
                ';
        }

        location /flush-metrics {
                set $aws_access_key AKIAIBF2BKMFXSCLCR4Q;
                set $aws_secret_key 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;
                set $aws_region us-east-1;
                set $aws_service sns;

                resolver 10.8.4.247;

                content_by_lua '
                    local BufferedAsyncLogger = require "logger.BufferedAsyncLogger"
                    local logger = BufferedAsyncLogger:new({
                        flush_length = 20,
                        sharedDict = "stats_all",
                        flushDestination = "/flush-metrics"
                    })
                    logger:flushMetrics()
                ';
        }
--- pipelined_requests eval
[
"GET /log-metrics",
"GET /log-metrics",
"POST /flush-metrics"
]
--- response_body_like eval
["","",".*PublishResult.*"]
--- error_code_like eval
[200,200,200]
--- no_error_log
[error]


=== TEST 3: flush some data to internal location
--- http_config eval: $::HttpConfig
--- config
        location /log-metrics {
                set $aws_access_key AKIAIBF2BKMFXSCLCR4Q;
                set $aws_secret_key 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;
                set $aws_region us-east-1;
                set $aws_service sns;

                resolver 10.8.4.247;

                content_by_lua '
                    local randomSeed = string.gsub(tostring(ngx.now()),"%.","")
                    local key = ngx.utctime() .."-".. math.random(randomSeed)

                    local allMetricValues = "\'publisherVal1\',".."\'consumerVal1\',".."\'applicationVal1\',".."\'serviceVal1\',".."\'region\',".."\'requestMethod\',".."\'status\',".. "\'guid\',"..
                                                    "\'guid\',".."\'timstamp\',".."\'ipAddress\',".."\'requestPath\'"

                    local BufferedAsyncLogger = require "logger.BufferedAsyncLogger"
                    local logger = BufferedAsyncLogger:new({
                        flush_length = 20,
                        sharedDict = "stats_all",
                        flushDestination = "/flush-metrics"
                    })
                    logger:logMetrics(key, allMetricValues)
                ';
        }

        location /flush-metrics {
                set $aws_access_key AKIAIBF2BKMFXSCLCR4Q;
                set $aws_secret_key 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;
                set $aws_region us-east-1;
                set $aws_service sns;

                resolver 10.8.4.247;
                content_by_lua '
                    local res = ngx.location.capture("/flush-location");
                    ngx.say(res.body)
                ';
        }
        location /flush-location {
            content_by_lua '
                local BufferedAsyncLogger = require "logger.BufferedAsyncLogger"
                local logger = BufferedAsyncLogger:new({
                    flush_length = 20,
                    sharedDict = "stats_all",
                    flushDestination = "/flush-metrics"
                })
                local req_body = logger:getDataFromSharedDict()
                ngx.say(req_body)
            ';
        }
--- pipelined_requests eval
[
"GET /log-metrics",
"GET /log-metrics",
"POST /flush-metrics"
]
--- response_body_like eval
["","",
" {\"headings\":['publisher','consumer','application','service','region','requestMethod','status','guid','guid','timstamp','ipAddress','requestPath'],\"values\":[['publisherVal','consumerVal','applicationVal','serviceVal','region','requestMethod','status','guid','guid','timstamp','ipAddress','requestPath'],['publisherVal1','consumerVal1','applicationVal1','serviceVal1','region','requestMethod','status','guid','guid','timstamp','ipAddress','requestPath']]} "
]
--- error_code_like eval
[200,200,200]
--- no_error_log
[error]
