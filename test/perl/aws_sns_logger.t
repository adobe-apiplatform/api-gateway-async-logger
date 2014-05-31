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

=== TEST 1: test that logs are sent to SNS
--- http_config eval: $::HttpConfig
--- config
        location /t {
            set $aws_access_key AKIAIBF2BKMFXSCLCR4Q;
            set $aws_secret_key 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;
            set $aws_region "us-east-1";
            set $aws_service "sns";
            set $analytics_topic_arn "arn:aws:sns:us-east-1:492299007544:apiplatform-dev-ue1-topic-analytics";

            resolver 10.8.4.247;

            content_by_lua '
                local BufferedAsyncLogger = require "api-gateway.logger.BufferedAsyncLogger"

                local logger = BufferedAsyncLogger:new({
                    flush_length = 2,
                    sharedDict = "stats_all",
                    backend = "api-gateway.logger.backend.AwsSnsLogger",
                    backend_opts = {
                        aws_region = ngx.var.aws_region,
                        sns_topic_arn = ngx.var.analytics_topic_arn,
                        method = "POST" -- NOT USED
                    }
                })
                logger:logMetrics("1", "value1")
                logger:logMetrics(2, "value2")
                logger:logMetrics(3, "value3")

                local dict =  ngx.shared.stats_all
                --ngx.say( dict:get("1") )
                ngx.say( dict:get(3) )
            ';
        }
--- request
GET /t
--- response_body
value1
value3
--- error_code: 200
--- no_error_log
[error]