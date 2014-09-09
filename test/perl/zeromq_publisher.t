# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

worker_connections(250);
master_process_enabled(1);
workers(4);
log_level('info');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 4);

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
    init_worker_by_lua '
        local function loadrequire(module)
            local function requiref(module)
                require(module)
            end
            local res = pcall(requiref,module)
            if not(res) then
                ngx.log(ngx.WARN, "Module ", module, " was not found.")
                return nil
            end
            return require(module)
        end
        -- when the ZmqModule is not present the script does not break
        local ZmqLogger = loadrequire("api-gateway.zmq.ZeroMQLogger")

        if (not ngx.zmqLogger ) and ( ZmqLogger ~= nil ) then
            ngx.log(ngx.INFO, "Starting new ZmqLogger on pid ", tostring(ngx.worker.pid()), " ...")
            ngx.zmqLogger = ZmqLogger:new()
            ngx.zmqLogger:connect(ZmqLogger.SOCKET_TYPE.ZMQ_PUB, "ipc:///tmp/xsub")
        end
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
                if ( ngx.zmqLogger ) then
                    ngx.zmqLogger:log("Ciresica are mere")
                    ngx.zmqLogger:log("Ciresel vine si cere")
                end
                ngx.say("Message should be sent")
            ';
        }
--- timeout: 20s
--- pipelined_requests eval
["GET /t"
]
--- response_body_like eval
["Message should be sent.*"
]
--- error_code_like eval
[200,200]
--- no_error_log
[error]
--- grep_error_log eval: qr/Starting new ZmqLogger on pid \d+/
--- grep_error_log_out eval
qr/(Starting new ZmqLogger on pid \d+){1,4}/





