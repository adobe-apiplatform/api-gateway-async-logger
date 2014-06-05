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

#=== TEST 1: test that logs are sent to SNS
#--- http_config eval: $::HttpConfig
#--- config
#        location /t {
#            set $aws_access_key ASIAIT6QKA53TLHC72EA;
#            set $aws_secret_key L8MJ1OcStvq79FEsEfv9mR8qvz5yURwxlPYmg76H;
#            set $aws_region "us-east-1";
#            set $aws_service "sns";
#            set $analytics_topic_arn "arn:aws:sns:us-east-1:492299007544:apiplatform-dev-ue1-topic-analytics";
#
#            resolver 10.8.4.247;
#
#            # content_by_lua '
#            #    ngx.say("OK")
#            #';
#
#            content_by_lua '
#                local BufferedAsyncLogger = require "api-gateway.logger.BufferedAsyncLogger"
#                ngx.say(ngx.now())
#                local logger = BufferedAsyncLogger:new({
#                    flush_length = 4,
#                    sharedDict = "stats_all",
#                    backend = "api-gateway.logger.backend.AwsSnsLogger",
#                    backend_opts = {
#                        aws_region = ngx.var.aws_region,
#                        aws_secret_key = ngx.var.aws_secret_key,
#                        aws_access_key = ngx.var.aws_access_key,
#                        sns_topic_arn = ngx.var.analytics_topic_arn,
#                        method = "POST" -- NOT USED
#                    }
#                })
#                for i=1,9 do
#                   logger:logMetrics(i, "value" .. tostring(i))
#                end
#                -- logger:logMetrics("1", "value1")
#                --logger:logMetrics(2, "value2")
#                --logger:logMetrics(3, "value3")
#                --logger:logMetrics(4, "value4")
#                --logger:logMetrics(5, "value5")
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


=== TEST 2: test that logs are sent to SNS with IAM user
--- http_config eval: $::HttpConfig
--- config
        location /get-iam-credentials/test {
            return 200 '{ "Code" : "Success",
                "LastUpdated" : "2014-06-04T20:59:45Z",
                "Type" : "AWS-HMAC",
                "AccessKeyId" : "ASIAI7ZTCN2NTZYMCSZA",
                "SecretAccessKey" : "tcAi+9LoSY+RGLDrHQawI3muBUmDW91WNEDDPhUJ",
                "Token" : "AQoDYXdzEGsa0AMwUApb2kR/0gLPF4wCajyGVfRqV1DRda0Uip7hIjjkqQdZ7FUOVSlcGw07asGbtbSrGw6+dAiLzZabYUOiPCTbkF4hPknxRh62OwIIvUy6Dqpua09E3s7BJTUdER7piesId5Lr3bX/qsAk19vmPd9kEiKahojIVGkt29bF448uUF8bZTc7+Du3a+cmWkRidnQuTdYysCpz5imUKPJSvUDLICLOHIu1re/chrQGMre2Bw+nsrxjehKiDy7WNyl4o2jW+QFZDD0ET5bKpK7qW9N1aJlzDyUazrYvpn+8cExBTGE00vs9pMPNyN9zzYyZO0jbSt+pY/YZD0Nj7B+pAQWUoLqu5KlVcsC9vT+5MD5eOt5X5KcEdqGk2U2dAjHjNSLVF9cETUnRf0RVJyvxyFtYj1NWS5W0VMQ/CLoc3vz761aAwkO+kebYJxbogZGiy5q1Q1N4LbqrxxzMM1bKYxGf+yDWu58RqVR94b2tKC5tuAaw+Zk09oaHLc65Qqs4Blz/JOXU1g8cPYSqvAmi4roS6Gd10x5ZdDBJmJhyo85qBekX2XgfpcAduXBmGZM84xRbGqp4SRhWo3MiPbrWeFR1rdQg95GhnyHnoVUbkOAB0CDjp7+cBQ==",
                "Expiration" : "2014-06-05T03:17:46Z" }';
        }

        location /t {
            set $aws_access_key ASIAIT6QKA53TLHC72EA;
            set $aws_secret_key L8MJ1OcStvq79FEsEfv9mR8qvz5yURwxlPYmg76H;
            set $aws_region "us-east-1";
            set $aws_service "sns";
            set $analytics_topic_arn "arn:aws:sns:us-east-1:492299007544:apiplatform-dev-ue1-topic-analytics";
            set $aws_iam_user "test";

            resolver 10.8.4.247;

            # content_by_lua '
            #    ngx.say("OK")
            #';

            content_by_lua '
                local BufferedAsyncLogger = require "api-gateway.logger.BufferedAsyncLogger"
                ngx.say(ngx.now())
                local logger = BufferedAsyncLogger:new({
                    flush_length = 4,
                    sharedDict = "stats_all",
                    backend = "api-gateway.logger.backend.AwsSnsLogger",
                    backend_opts = {
                        aws_region = ngx.var.aws_region,
                        aws_iam_user = {
                            iam_user = ngx.var.aws_iam_user,
                            -- optional URL, will default to AWS default URL
                            security_credentials_host = "127.0.0.1",
                            security_credentials_port = "1989",
                            security_credentials_url = "/get-iam-credentials/",
                            security_credentials_timeout = 15,
                            sharedDict = "stats_all",
                        },
                        sns_topic_arn = ngx.var.analytics_topic_arn,
                        method = "POST" -- NOT USED
                    }
                })
                for i=1,9 do
                   logger:logMetrics(i, "value" .. tostring(i))
                end
                -- logger:logMetrics("1", "value1")
                --logger:logMetrics(2, "value2")
                --logger:logMetrics(3, "value3")
                --logger:logMetrics(4, "value4")
                --logger:logMetrics(5, "value5")
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




