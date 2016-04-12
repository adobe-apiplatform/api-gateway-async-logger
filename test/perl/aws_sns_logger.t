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
    lua_shared_dict stats_all 1m;
    lua_package_path 'src/lua/?.lua;/usr/local/lib/lua/?.lua;;';
    lua_package_cpath 'src/lua/?.so;;';
    init_by_lua '
        local v = require "jit.v"
        v.on("$Test::Nginx::Util::ErrLogFile")
        require "resty.core"
    ';
    resolver @nameservers;

    client_body_temp_path /tmp/;
    proxy_temp_path /tmp/;
    fastcgi_temp_path /tmp/;
_EOC_


#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: test that logs are sent to SNS
--- http_config eval: $::HttpConfig
--- config
        location /t {
            set $aws_access_key AKIAIBF2BKMFXSCLCR4Q;
            set $aws_secret_key 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;
            set $aws_region "us-east-1";
            set $aws_service "sns";
            set $analytics_topic_arn "arn:aws:sns:us-east-1:492299007544:apiplatform-dev-ue1-topic-analytics";

            content_by_lua '
                local BufferedAsyncLogger = require "api-gateway.logger.BufferedAsyncLogger"
                local logger = BufferedAsyncLogger:new({
                    flush_length = 4,
                    sharedDict = "stats_all",
                    backend = "api-gateway.logger.backend.AwsSnsLogger",
                    backend_opts = {
                        aws_region = ngx.var.aws_region,
                        aws_secret_key = ngx.var.aws_secret_key,
                        aws_access_key = ngx.var.aws_access_key,
                        sns_topic_arn = ngx.var.analytics_topic_arn,
                        method = "POST" -- NOT USED
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
GET /t
--- response_body
OK
--- error_code: 200
--- no_error_log
[error]
--- more_headers
X-Test: test

#
# The following test is commented for now as it requires IAM Credentials and you need to get new ones when you want to run the test
#
#=== TEST 2: test that logs are sent to SNS with IAM user
#--- http_config eval: $::HttpConfig
#--- config
#        location = /latest/meta-data/iam/security-credentials/test {
#            return 200 '{ "Code" : "Success",
#                "LastUpdated" : "2014-06-04T20:59:45Z",
#                "Type" : "AWS-HMAC",
#                "AccessKeyId" : "ASIAITJJEWHZDNKMRXRA",
#                "SecretAccessKey" : "hC5BU1kTFJcYpmpThvGn/he9zY7ZVMQrJ/Ittsjm",
#                "Token" : "AQoDYXdzEPX//////////wEa4AM198qcWT7bcpGsLC1Yzbi/qUxXPi6GUtUIDLug9ONSzC5YVazCwRj7s3lydZKjebl0581RnmWndcX6tzhFtHuJoUBNqlZVxxI+SsWMY5jpOkF7xNJtp2aD92BlXxBVpmNpkRH/zWsaF05KfW5q02qJv8Vyr96Bh4NWBlcAZdxX/jOqbQEgW9bsW2hfTrA4y6/TCEZS2rd8cHI5NhZXZJfxzAbL+CUvsLGLGBNMz+j24tFP/wIogrf/lvZLuWVOKZi3/l5+NtyGpbDJMdv1sj0ynDlEYrtz2P4DGsH0JO3fVVy7C+vrmEKihFOBhh6N0TUKLR8VGzk+r6fm+jxDgtVKRYqIhGyLSWHbU8F9vOxo5BMmYnaiVscAeF/NbmtEu+wkscbErUHbrbORi/12wYmQbDANPc29HXFLEMrQywE5Vyyy5YE3eJgL1sn1RA9ejGshoZ43K1grok+wE/yyF/nRUepQEU8A4zZ39UMsNPXGkaEjfvKBVWx0/BxaZywL6HBEzAyR6uwGA6uIWZ4dx5+vx8aGLLitNtKzoait+B6BSWAmzvUrIy8pRKBoi4EqgdTs2gs1kVeIJf35B/CMO3Vidu/NGKgDmVme1hmnhZj+g9bBLc1Ag32gMpLtuCLbKgUgp9aSpAU=",
#                "Expiration" : "2014-06-05T03:17:46Z" }';
#        }
#
#        location /t {
#            set $aws_region "us-east-1";
#            set $aws_service "sns";
#            set $analytics_topic_arn "arn:aws:sns:us-east-1:889681731264:apip-stage-ue1-topic-analytics";
#            set $aws_iam_user "test";
#
#            content_by_lua '
#                local BufferedAsyncLogger = require "api-gateway.logger.BufferedAsyncLogger"
#                local logger = BufferedAsyncLogger:new({
#                    flush_length = 4,
#                    sharedDict = "stats_all",
#                    backend = "api-gateway.logger.backend.AwsSnsLogger",
#                    backend_opts = {
#                        aws_region = ngx.var.aws_region,
#                        aws_iam_user = {
#                            iam_user = ngx.var.aws_iam_user,
#                            -- optional URL, will default to AWS default URL
#                            security_credentials_host = "127.0.0.1",
#                            security_credentials_port = "1989",
#                            security_credentials_timeout = 15,
#                            shared_cache_dict = "stats_all"
#                        },
#                        sns_topic_arn = ngx.var.analytics_topic_arn,
#                        method = "POST" -- NOT USED
#                    }
#                })
#                for i=1,9 do
#                   logger:logMetrics(i, "value" .. tostring(i))
#                end
#                ngx.sleep(2)
#                ngx.say("OK")
#            ';
#        }
#--- request
#GET /t
#--- response_body
#OK
#--- error_code: 200
#--- no_error_log
#[error]




