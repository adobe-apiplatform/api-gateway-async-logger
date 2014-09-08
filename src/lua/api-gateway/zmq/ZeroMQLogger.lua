--
-- Logs all messages to a ZeroMQ queue
-- Usage:
-- init_worker_by_lua '
--        local ZmqLogger = require "api-gateway.zmq.ZeroMQLogger"
--        if not ngx.zmqLogger then
--            ngx.log(ngx.INFO, "Starting new ZmqLogger .. ")
--            ngx.zmqLogger = ZmqLogger:new()
--            ngx.zmqLogger:connect(ZmqLogger.SOCKET_TYPE.ZMQ_PUB, "ipc:///tmp/xsub")
--        end
--    ';
--

local setmetatable = setmetatable
local error = error
local ffi = require "ffi"
local ffi_new = ffi.new
local ffi_str = ffi.string
local C = ffi.C
local zmqlib = ffi.load("zmq")
local czmq = ffi.load("czmq")

local SOCKET_TYPE = {
    ZMQ_PAIR = 0,
    ZMQ_PUB = 1,
    ZMQ_SUB = 2,
    ZMQ_REQ = 3,
    ZMQ_REP = 4,
    ZMQ_DEALER = 5,
    ZMQ_ROUTER = 6,
    ZMQ_PULL = 7,
    ZMQ_PUSH = 8,
    ZMQ_XPUB = 9,
    ZMQ_XSUB = 10,
    ZMQ_STREAM = 11
}

local _M = { _VERSION = '0.1' }
local mt = { __index = _M }
_M.SOCKET_TYPE = SOCKET_TYPE

ffi.cdef[[
    typedef struct _zctx_t zctx_t;
    extern volatile int zctx_interrupted;
    zctx_t * zctx_new (void);
    void * zsocket_new (zctx_t *self, int type);
    int zsocket_connect (void *socket, const char *format, ...);
    int zsocket_bind (void *socket, const char *format, ...);

    void zctx_destroy (zctx_t **self_p);
    void zsocket_destroy (zctx_t *self, void *socket);

    void zsocket_set_subscribe (void *zocket, const char * subscribe);
    int zstr_send (void *socket, const char *string);

    int zmq_ctx_destroy (void *context);
]]


local ctx_v = czmq.zctx_new()
local ctx = ffi_new("zctx_t *", ctx_v)
local socketInst

local check_worker_delay = 5
local function check_worker_process(premature)
    if not premature then
        local ok, err = ngx.timer.at(check_worker_delay, check_worker_process)
        if not ok then
            ngx.log(ngx.ERR, "failed to create timer to check worker process: ", err)
        end
    else
        ngx.log(ngx.INFO, "Terminating ZMQ context due to worker termination ...")
        -- this should be called when the worker is stopped
        zmqlib.zmq_ctx_destroy(ctx)
    end
end

local ok, err = ngx.timer.at(check_worker_delay, check_worker_process)
if not ok then
    ngx.log(ngx.ERR, "failed to create timer to check worker process: ", err)
end

function _M.new(self)
    return setmetatable({}, mt)
end

function _M.connect(self, socket_type, socket_address)
    if ( socket_type == nil ) then
        error("Socket type must be provided." )
    end
    if ( socket_address == nil ) then
        error("Socket address must be provided.")
    end
    self.socketInst = czmq.zsocket_new(ctx, socket_type)
    local socket_bound = czmq.zsocket_connect(self.socketInst, socket_address)
--    local socket_bound = czmq.zsocket_connect(self.socketInst, "ipc:///tmp/xsub")
    --local socket_bound = czmq.zsocket_connect(self.socketInst, "tcp://127.0.0.1:6000")
end

function _M.log(self, msg)
    local send_result = "NOT-SENT"
    if ( msg ~= nil and #msg > 0 ) then
        send_result = czmq.zstr_send(self.socketInst, msg )
    end

    ngx.log(ngx.DEBUG, "Message [", tostring(msg), "], sent with result=", tostring(send_result), ", from pid=", ngx.worker.pid() )
end

function _M.disconnect(self)
    --czmq.zsocket_destroy(ctx, self.socketInst)
    zmqlib.zmq_ctx_destroy(ctx)
end


-- wait for the connection to complete then send the message, otherwise it is not received
--ngx.sleep(0.100)

return _M