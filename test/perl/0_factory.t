#!/usr/bin/perl
# vim:set ft= ts=4 sw=4 et fdm=marker:
use strict;
use warnings;
use Test::More;
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 4)-2;

my $pwd = cwd();

# try to read the nameservers used by the system resolver:
my @nameservers;
if (open my $in, "/etc/resolv.conf") {
    while (<$in>) {
        if (/^\s*nameserver\s+(\d+(?:\.\d+){3})(?:\s+|$)/) {
            push @nameservers, $1;
            if (@nameservers > 10) {
                last;
            }
        }
    }
    close $in;
}

if (!@nameservers) {
    # default to Google's open DNS servers
    push @nameservers, "8.8.8.8", "8.8.4.4";
}


warn "Using nameservers: \n@nameservers\n";

our $HttpConfig = <<_EOC_;
    # lua_package_path "$pwd/scripts/?.lua;;";
    lua_package_path 'src/lua/?.lua;/usr/local/lib/lua/?.lua;;';
    # lua_package_cpath 'src/lua/?.so;;';

    init_by_lua '
        local v = require "jit.v"
        v.on("$Test::Nginx::Util::ErrLogFile")
        require "resty.core"
    ';
    resolver @nameservers;
    lua_shared_dict stats_all 1m;

    client_body_temp_path /tmp/;
    proxy_temp_path /tmp/;
    fastcgi_temp_path /tmp/;
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: test that factory return null when no name is provided
--- http_config eval: $::HttpConfig
--- config
        error_log ../test-logs/factory_test1_error.log debug;

        location /test {
            content_by_lua '
                local logger_factory = require "api-gateway.logger.factory"
                local l = logger_factory:getLogger()
                local result = "l=" .. tostring(l)

                l = logger_factory:getLogger("test-logger")
                result = result .. ",l2=" .. tostring(l)

                l = logger_factory:getLogger("test-logger", "inexisting.module")
                result = result .. ",l3=" .. tostring(l)

                result = result .. ",hasLogger=" .. tostring(logger_factory:hasLogger("test"))

                ngx.say(result)
           ';
        }

--- request
GET /test
--- response_body
l=nil,l2=nil,l3=nil,hasLogger=false
--- error_code: 200
--- no_error_log
[error]
--- more_headers
X-Test: test


=== TEST 2: test that factory returns the same instance of the logger for consecutive gets
--- http_config eval: $::HttpConfig
--- config
        error_log ../test-logs/factory_test2_error.log debug;

        location /test {

            content_by_lua '
                local logger_factory = require "api-gateway.logger.factory"
                local x = require "api-gateway.logger.backend.AwsKinesisLogger"

                local logger_module = "api-gateway.logger.BufferedAsyncLogger"
                local logger_opts = {
                            flush_length = 4,
                            sharedDict = "stats_all",
                            backend = "api-gateway.logger.backend.AwsKinesisLogger",
                            backend_opts = {
                                aws_region = "us-east-1",
                                kinesis_stream_name = "test-stream",
                                aws_credentials = {
                                    provider = "api-gateway.aws.AWSIAMCredentials",
                                    shared_cache_dict = "stats_all",
                                    security_credentials_timeout = 60 * 60 * 24,
                                    security_credentials_host = "127.0.0.1",      -- test only
                                    security_credentials_port = $TEST_NGINX_PORT -- test only
                                }
                            }
                        }

                local logger = logger_factory:getLogger("mylogger", logger_module, logger_opts)
                local logger_2 = logger_factory:getLogger("mylogger")
                if (logger ~= nil and logger == logger_2) then
                    ngx.say("OK")
                    return
                end
                ngx.say("logger_2 instance should have been returned from cache. logger=" .. tostring(logger) ..
                            "logger_2=" .. tostring(logger_2))
            ';
        }
--- request
GET /test
--- response_body
OK
--- error_code: 200
--- no_error_log
[error]
--- more_headers
X-Test: test

