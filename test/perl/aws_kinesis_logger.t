# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use warnings;
use strict;
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 4)-1;

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
    lua_package_cpath 'src/lua/?.so;;';

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


=== TEST 1: test that the logs can be pushed to kinesis
--- http_config eval: $::HttpConfig
--- config
        error_log ../test-logs/aws_kinesis_logger_test1_error.log debug;

        location = /latest/meta-data/iam/security-credentials/ {
            return 200 'test-iam-user';
        }

        location = /latest/meta-data/iam/security-credentials/test-iam-user {
            set_by_lua $expiration '
                            local offset = os.time() - os.time(os.date("!*t"))
                            return os.date("%Y-%m-%dT%H:%M:%SZ", os.time() + math.abs(offset) + 20)
                        ';
            return 200 '{
                          "Code" : "Success",
                          "LastUpdated" : "2014-11-03T01:56:20Z",
                          "Type" : "AWS-HMAC",
                          "AccessKeyId" : "$TEST_NGINX_AWS_ACCESS_KEY_ID",
                          "SecretAccessKey" : "$TEST_NGINX_AWS_SECRET_ACCESS_KEY",
                          "Token" : "$TEST_NGINX_AWS_SECURITY_TOKEN",
                          "Expiration" : "$expiration"
                        }';
        }

        location /test {
            set $aws_region us-east-1;
            set $kinesis_stream_name "test-stream";

            content_by_lua '
                local BufferedAsyncLogger = require "api-gateway.logger.BufferedAsyncLogger"
                local logger = BufferedAsyncLogger:new({
                    flush_length = 4,
                    sharedDict = "stats_all",
                    backend = "api-gateway.logger.backend.AwsKinesisLogger",
                    backend_opts = {
                        aws_region = ngx.var.aws_region,
                        kinesis_stream_name = ngx.var.kinesis_stream_name,
                        aws_credentials = {
                            provider = "api-gateway.aws.AWSIAMCredentials",
                            security_credentials_host = "127.0.0.1",      -- test only
                            security_credentials_port = $TEST_NGINX_PORT, -- test only
                            security_credentials_timeout = 60 * 60 * 24,
                            shared_cache_dict = "stats_all"
                        }
                    }
                })
                for i=1,9 do
                   logger:logMetrics(i, "value" .. tostring(i))
                end
                ngx.sleep(2)
                ngx.say("OK")
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