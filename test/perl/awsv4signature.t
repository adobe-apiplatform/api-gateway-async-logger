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

=== TEST 2: test aws s4 signature
--- http_config eval: $::HttpConfig
--- config
        location /test-signature {
            resolver 10.8.4.247;
            set $aws_access_key AKIAIBF2BKMFXSCLCR4Q;
            set $aws_secret_key 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;
            set $aws_region us-east-1;
            set $aws_service sns;
            set $aws_request_code aws4_request;

            # set_by_lua_file $query /Users/ddascal/Projects/github_adobe/api-gateway-logger/src/lua/aws/sdb.lua;
            # rewrite .* /?$query break;

            set $x_amz_date "TBD";
            set $x_amz_date_short 'TBD';
            set_by_lua $auth_signature '
                local AWSV4S = require "aws.AwsV4Signature"
                local awsAuth =  AWSV4S:new( {
                                               aws_region  = ngx.var.aws_region,
                                               aws_service = ngx.var.aws_service
                                          })
                return awsAuth:getSignature()
            ';

            # proxy_pass https://$aws_service.$aws_region.amazonaws.com/;
            proxy_pass https://$aws_service.$aws_region.amazonaws.com/$request_uri;
            proxy_set_header Authorization "AWS4-HMAC-SHA256 Credential=$aws_access_key/$x_amz_date_short/$aws_region/$aws_service/$aws_request_code,SignedHeaders=host;x-amz-date,Signature=$auth_signature";

            proxy_set_header X-Amz-Date $x_amz_date;
        }

--- more_headers
X-Test: test
--- request
POST /test-signature?Message=hello_from_nginx&TopicArn=arn:aws:sns:us-east-1:492299007544:apiplatform-dev-ue1-topic-analytics&Action=Publish
--- response_body eval
["OK"]
--- error_code: 200
--- no_error_log
[error]




