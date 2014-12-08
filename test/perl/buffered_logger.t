# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

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

=== TEST 1: test flush works in a light thread
--- http_config eval: $::HttpConfig
--- config
        location /t {
            content_by_lua '
                local _M = {}
                function _M:new(o)
                    o = o or {}
                    setmetatable(o, self)
                    self.__index = self
                    self.message = "I am being executed via timer"
                    return o
                end
                local function timer_callback(premature, self)
                    ngx.log(ngx.WARN, self.message)
                end

                function _M:doSomethingAsync()
                   ngx.timer.at(0.001, timer_callback, self)
                end

                local mInst = _M:new()
                mInst:doSomethingAsync()
                ngx.say("timer is pending")
                -- wait for the async to happen
                ngx.sleep(0.100)
            ';


        }
--- request
GET /t
--- response_body
timer is pending
--- error_code: 200
--- no_error_log
[error]
--- grep_error_log eval: qr/I am being executed via timer *?/
--- grep_error_log_out
I am being executed via timer



=== TEST 2: test that logs are buffered in the given dictionary
--- http_config eval: $::HttpConfig
--- config
        location /t {
            content_by_lua '
                local BufferedAsyncLogger = require "api-gateway.logger.BufferedAsyncLogger"

                local logger = BufferedAsyncLogger:new({
                    flush_length = 20,
                    sharedDict = "stats_all",
                    backend = "api-gateway.logger.backend.HttpLogger"
                })
                logger:logMetrics("1", "value1")
                logger:logMetrics(2, "value2")

                local dict =  ngx.shared.stats_all
                ngx.say( dict:get("1") )
                ngx.say( dict:get(2) )
            ';
        }
--- request
GET /t
--- response_body
value1
value2
--- error_code: 200
--- no_error_log
[error]

=== TEST 3: test that logs are flushed
--- http_config eval: $::HttpConfig
--- config
        location /t {
            content_by_lua '
                local BufferedAsyncLogger = require "api-gateway.logger.BufferedAsyncLogger"

                local logger = BufferedAsyncLogger:new({
                    flush_length = 2,
                    sharedDict = "stats_all",
                    backend = "api-gateway.logger.backend.HttpLogger",
                    backend_opts = {
                        host = "127.0.0.1",
                        port = "1989",
                        url = "/flush-location",
                        method = "POST"
                    }
                })
                logger:logMetrics("1", "value1")
                logger:logMetrics(2, "value2")
                logger:logMetrics(3, "value3")
                ngx.sleep(0.500)
                ngx.say("OK")
            ';
        }
        location /flush-location {
            lua_need_request_body on;
            content_by_lua '
                ngx.say("START")
                ngx.say( ngx.var.request_body )
                ngx.say("END")
                ngx.log(ngx.WARN, "TO BE LOGGED: " .. ngx.var.request_body)
            ';
        }
--- request
GET /t
--- response_body
OK
--- error_code: 200
--- no_error_log
[error]
--- grep_error_log eval: qr/TO BE LOGGED: value1,value2,*?/
--- grep_error_log_out
TO BE LOGGED: value1,value2


=== TEST 4: test limit of concurrency background threads
--- http_config eval: $::HttpConfig
--- config
        location /t {
            content_by_lua '
                local BufferedAsyncLogger = require "api-gateway.logger.BufferedAsyncLogger"

                local logger = BufferedAsyncLogger:new({
                    flush_length = 200,
                    flush_concurrency = 3,
                    sharedDict = "stats_all",
                    backend = "api-gateway.logger.backend.HttpLogger",
                    backend_opts = {
                        host = "127.0.0.1",
                        port = "1989",
                        url = "/flush-location",
                        method = "POST"
                    }
                })
                for i=1,500 do
                   logger:logMetrics(i, "value" .. tostring(i))
                end
                local dict =  ngx.shared.stats_all
                ngx.say( "1. Pending timers left:" .. dict:get("pendingTimers") )
                ngx.sleep(0.500)
                ngx.say( "2. Pending timers left:" .. dict:get("pendingTimers") )
            ';
        }
        location /flush-location {
            lua_need_request_body on;
            content_by_lua '
                ngx.log(ngx.WARN, "Flush content: " .. ngx.var.request_body)
            ';
        }
--- request
GET /t
--- response_body
1. Pending timers left:3
2. Pending timers left:0
--- error_code: 200
--- no_error_log
[error]
--- grep_error_log eval: qr/Flush content: *?/
--- grep_error_log_out
Flush content:
Flush content:
Flush content:


=== TEST 5: test data is flushed if the flush_interval is reached, even when the buffer is not full
--- http_config eval: $::HttpConfig
--- config
        location /t {
            content_by_lua '
                local BufferedAsyncLogger = require "api-gateway.logger.BufferedAsyncLogger"

                local logger = BufferedAsyncLogger:new({
                    flush_length = 200,
                    flush_concurrency = 3,
                    flush_interval = 0.300,
                    sharedDict = "stats_all",
                    backend = "api-gateway.logger.backend.HttpLogger",
                    backend_opts = {
                        host = "127.0.0.1",
                        port = "1989",
                        url = "/flush-location",
                        method = "POST"
                    }
                })

                logger:logMetrics("1", "value1")

                local dict =  ngx.shared.stats_all
                local ts1 = dict:get("lastFlushTimestamp")
                ngx.say( "1st flush timestamp:" .. tostring(ts1) )
                -- wait for some time just to expire flush_interval then add a new metric to trigger the push
                ngx.sleep(0.400)
                logger:logMetrics(3, "value3")
                -- wait for some time again
                ngx.sleep(0.300)
                logger:logMetrics(4, "value4")
                -- make sure the flush_interval will expire again then add a new metric
                ngx.sleep(0.100)
                local ts2 = dict:get("lastFlushTimestamp")
                ngx.say( "2nd flush timestamp:" .. tostring(ts2) )
                logger:logMetrics(5, "value5")
                assert ( ts2-ts1 < 0.500 and ts2-ts1 > 0.300, "Flush was not triggered correctly")
            ';
        }
        location /flush-location {
            lua_need_request_body on;
            content_by_lua '
                ngx.log(ngx.WARN, "Flush content: " .. ngx.var.request_body)
            ';
        }
--- timeout: 20s
--- request
GET /t
--- response_body_like eval
"1st flush timestamp:\\d+\\.\\d+\n2nd flush timestamp:\\d+"
--- error_code: 200
--- no_error_log
[error]
--- grep_error_log eval: qr/Flush content: value\d,value\d, *?/
--- grep_error_log_out
Flush content: value1,value3,
Flush content: value4,value5,

