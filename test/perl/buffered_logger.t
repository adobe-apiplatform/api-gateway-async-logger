# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 4) - 3;

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

#=== TEST 1: test that logs are buffered in the given dictionary
#--- http_config eval: $::HttpConfig
#--- config
#        location /t {
#            content_by_lua '
#                local BufferedAsyncLogger = require "api-gateway.logger.BufferedAsyncLogger"
#
#                local logger = BufferedAsyncLogger:new({
#                    flush_length = 20,
#                    sharedDict = "stats_all",
#                    backend = "api-gateway.logger.backend.HttpLogger"
#                })
#                logger:logMetrics("1", "value1")
#                logger:logMetrics(2, "value2")
#
#                local dict =  ngx.shared.stats_all
#                ngx.say( dict:get("1") )
#                ngx.say( dict:get(2) )
#            ';
#        }
#--- request
#GET /t
#--- response_body
#value1
#value2
#--- error_code: 200
#--- no_error_log
#[error]

=== TEST 2: test that logs are flushed
--- http_config eval: $::HttpConfig
--- config
        location /t {
            resolver 10.8.4.247;
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
--- grep_error_log eval: qr/TO BE LOGGED: ,value1,value2,*?/
--- grep_error_log_out
TO BE LOGGED: ,value1,value2
