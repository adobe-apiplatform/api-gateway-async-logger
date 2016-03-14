# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use strict;
use warnings;
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 4) - 6;

my $pwd = cwd();

our $HttpConfig = <<_EOC_;
    # lua_package_path "$pwd/scripts/?.lua;;";
    lua_shared_dict stats_all 20m;
    # a shared dict for storing log messages and do assertions on
    lua_shared_dict test_dict 1m;

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
        error_log ../test-logs/buffered_logger_test1_error.log debug;
        location /t {
            content_by_lua '
                local test_message = ""

                local _M = {}
                function _M:new(o)
                    o = o or {}
                    setmetatable(o, self)
                    self.__index = self
                    self.message = "I am being executed via timer"
                    return o
                end
                local function timer_callback(premature, self)
                    test_message = test_message .. self.message
                end

                function _M:doSomethingAsync()
                   ngx.timer.at(0.001, timer_callback, self)
                end

                local mInst = _M:new()
                mInst:doSomethingAsync()
                ngx.print("timer is pending and message is ")
                -- wait for the async to happen
                ngx.sleep(0.110)
                ngx.say(test_message)
            ';


        }
--- request
GET /t
--- response_body
timer is pending and message is I am being executed via timer
--- error_code: 200
--- no_error_log
[error]



=== TEST 2: test that logs are buffered in the given dictionary
--- http_config eval: $::HttpConfig
--- config
        error_log ../test-logs/buffered_logger_test2_error.log debug;
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
                ngx.say(logger:getCount())
            ';
        }
--- request
GET /t
--- response_body
value1
value2
2
--- error_code: 200
--- no_error_log
[error]

=== TEST 3: test that logs are flushed
--- http_config eval: $::HttpConfig
--- config
        error_log ../test-logs/buffered_logger_test3_error.log debug;
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
                local pending_threads = 0
                local running_threads = 0
                logger:logMetrics("1", "value1")
                pending_threads = logger:get_pending_threads()
                if (pending_threads > 0) then
                    ngx.say("pending_threads should have been 0")
                end
                logger:logMetrics(2, "value2")
                pending_threads = logger:get_pending_threads()
                if (pending_threads ~= 1) then
                    ngx.say("pending_threads should have been 1")
                end
                logger:logMetrics(3, "value3")
                pending_threads = logger:get_pending_threads()
                if (pending_threads ~= 1) then
                    ngx.say("pending_threads should have been 1 as no new ")
                end
                if (logger:getCount() ~= 3) then
                    ngx.say("Counter should have been 3")
                end
                ngx.sleep(0.100) -- threads are scheduled after max 100ms
                running_threads = logger:get_running_threads()
                if (running_threads ~= 1) then
                    ngx.say("there should have been 1 running_thread after 100ms")
                end
                pending_threads = logger:get_pending_threads()
                if (pending_threads ~= 0) then
                    ngx.say("pending_threads should have been 0 as there is a running thread")
                end
                if (logger:getCount() ~= 1) then
                    ngx.say("Counter should have been 1 as 2 logs should have been flushed")
                end

                ngx.sleep(0.500)
                local test_dict = ngx.shared.test_dict
                ngx.say(tostring(test_dict:get("flush_location_body")))
            ';
        }
        location /flush-location {
            lua_need_request_body on;
            content_by_lua '
                ngx.sleep(0.200)
                ngx.say("START")
                ngx.say( ngx.var.request_body )
                ngx.say("END")
                ngx.log(ngx.WARN, "TO BE LOGGED: " .. ngx.var.request_body)
                local test_dict = ngx.shared.test_dict
                test_dict:set("flush_location_body", ngx.var.request_body)
            ';
        }
--- request
GET /t
--- response_body
value1,value2
--- error_code: 200
--- no_error_log
[error]


=== TEST 4: test limit of concurrency background threads
--- http_config eval: $::HttpConfig
--- config
        error_log ../test-logs/buffered_logger_test4_error.log debug;
        location /t {
            content_by_lua '
                local BufferedAsyncLogger = require "api-gateway.logger.BufferedAsyncLogger"

                local logger = BufferedAsyncLogger:new({
                    flush_length = 200,
                    flush_concurrency = 5,
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
                ngx.say("1. Total logs:" .. logger:getCount())
                ngx.say("1. Pending threads left:" .. logger:get_pending_threads())
                ngx.sleep(0.500)
                ngx.say("2. Pending threads left:" .. logger:get_pending_threads())
                ngx.say("3. Running threads left:" .. logger:get_running_threads())
                ngx.say("4. Total logs left:" .. logger:getCount())
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
1. Total logs:500
1. Pending threads left:2
2. Pending threads left:0
3. Running threads left:0
4. Total logs left:100
--- error_code: 200
--- no_error_log
[error]


=== TEST 5: test flush_throughput limit is respected
--- http_config eval: $::HttpConfig
--- config
        error_log ../test-logs/buffered_logger_test5_error.log debug;
        location /t {
            content_by_lua '
                local BufferedAsyncLogger = require "api-gateway.logger.BufferedAsyncLogger"

                local logger = BufferedAsyncLogger:new({
                    flush_length = 20,
                    flush_throughput = 50,  -- this limits max logs / SECOND to be flushed
                    flush_interval = 1.100,
                    flush_concurrency = 5,
                    sharedDict = "stats_all",
                    backend = "api-gateway.logger.backend.HttpLogger",
                    backend_opts = {
                        host = "127.0.0.1",
                        port = "1989",
                        url = "/flush-location",
                        method = "POST"
                    }
                })
                for i=1,70 do
                   logger:logMetrics(i, "value" .. tostring(i))
                end
                ngx.say("1. Total logs:" .. logger:getCount())
                ngx.say("1. Pending threads left:" .. logger:get_pending_threads())
                ngx.sleep(0.500)
                ngx.say("2. Pending threads left:" .. logger:get_pending_threads())
                ngx.say("3. Running threads left:" .. logger:get_running_threads())
                ngx.sleep(0.650) -- wait just enough to expire flush_interval
                logger:logMetrics(71, "value71")  -- trigger the flush
                ngx.say("4. Pending threads left:" .. logger:get_pending_threads())
                ngx.sleep(0.100)
                ngx.say("5. Pending threads left:" .. logger:get_pending_threads())
                ngx.say("6. Running threads left:" .. logger:get_running_threads())
                -- at this point there should only be 1 log left in the buffer
                ngx.say("7. Total logs left:" .. logger:getCount())
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
1. Total logs:70
1. Pending threads left:3
2. Pending threads left:0
3. Running threads left:0
4. Pending threads left:1
5. Pending threads left:0
6. Running threads left:0
7. Total logs left:1
--- error_code: 200
--- no_error_log
[error]


=== TEST 6: test data is flushed if the flush_interval is reached, even when the buffer is not full
--- http_config eval: $::HttpConfig
--- config
        error_log ../test-logs/buffered_logger_test6_error.log debug;

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

                ngx.sleep(0.400)                -- wait to expire the 0.300 flush_interval
                logger:logMetrics(3, "value3")  -- trigger the flush
                local pending_threads = logger:get_pending_threads()
                if (pending_threads ~= 1) then
                    ngx.say("pending_threads should have been 1")
                end
                ngx.sleep(0.150)                    -- wait for some time to flush the logs

                logger:logMetrics(4, "value4")      -- add a new metric
                ngx.sleep(0.100)                    -- wait a little more but not to expire the flush_interval again
                logger:logMetrics(5, "value5")      -- this metric should not be sent as flush_interval did not expire

                local ts2 = dict:get("lastFlushTimestamp")
                ngx.say( "2nd flush timestamp:" .. tostring(ts2) )
                if (ts2-ts1 > 0.500 or ts2-ts1 < 0.300) then
                    ngx.say("Flush was not triggered correctly.")
                end
                ngx.say("Last flush content:", ngx.shared.test_dict:get("flush_location_body"))
            ';
        }
        location /flush-location {
            lua_need_request_body on;
            content_by_lua '
                ngx.log(ngx.WARN, "Flush content: " .. ngx.var.request_body)
                local test_dict = ngx.shared.test_dict
                test_dict:set("flush_location_body", ngx.var.request_body)
            ';
        }
--- timeout: 20s
--- request
GET /t
--- response_body_like eval
"1st flush timestamp:\\d+\\.\\d+\n2nd flush timestamp:\\d+.*Last flush content"
--- error_code: 200
--- no_error_log
[error]

