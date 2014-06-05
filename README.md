api-gateway-logger
==================

Performant async event logger.


Loggers
=======

BufferedAsyncLogger
-------------------
Sends an aggregated set of logs to a backend system.
The logs are sent when one of the following criteria is met:

 * a configurable max buffer size ( `flush_buffer` ) is reached . Default value is 10.
 * a configurable time interval has elapsed ( `flush_interval` ). Default value is 5 seconds.
 * the number of concurrent background threads sending log data is not reached. By default there can be 3 concurrent background threads.

The BufferedAsyncLogger flushes data asynchronously and non-blocking to a configured backend system.
It uses Lua's cosoket API to send data to an HTTP backend.
Data is send asynchronously using via ngx.timer.at API which schedules a background non-blocking light thread.
This thread is completely decoupled from the main request.

In high traffic conditions you can configure how many concurrent threads to be used for flushing logs.
Each thread is occupying a worker connection so make sure to configure nginx with enough worker connections.

Example:

``` nginx

    location /t {
        resolver 10.8.4.247;
        content_by_lua '
            local BufferedAsyncLogger = require "api-gateway.logger.BufferedAsyncLogger"

            local logger = BufferedAsyncLogger:new({
                flush_length = 200,
                flush_concurrency = 3,
                flush_interval = 0.300,
                sharedDict = "stats_all",
                backend = "api-gateway.logger.backend.HttpLogger",
                -- testing backend location
                backend_opts = {
                    host = "127.0.0.1",
                    port = "1989",
                    url = "/flush-location",
                    method = "POST"
                }
            })
            logger:logMetrics("1", "value1")
            logger:logMetrics(2, "value2")
        ';
    }
    location /flush-location {
        lua_need_request_body on;
        content_by_lua '
            ngx.log(ngx.WARN, "Flush content: " .. ngx.var.request_body)
        ';
    }
```

Backend systems
===============



HttpLogger backend
------------------
Sends data via POST to an HTTP location

AwsSnsLogger backend
--------------------
Sends data to the AWS SNS, which can then forward the logs to an SQS


Developer guide
===============

## Install the api-gateway first
 Since this module is running inside the `api-gateway`, make sure the api-gateway binary is installed under `/usr/local/sbin`.
 You should have 2 binaries in there: `api-gateway` and `nginx`, the latter being only a symbolik link.

## Update git submodules
```
git submodule update --init --recursive
```

## Running the tests
The tests are based on the `test-nginx` library.
This library is added a git submodule under `test/resources/test-nginx/` folder, from `https://github.com/agentzh/test-nginx`.

Test files are located in `test/perl`.
The other libraries such as `Redis`, `test-nginx` are located in `test/resources/`.
Other files used when running the test are also located in `test/resources`.

## Build locally
 ```
sudo LUA_LIB_DIR=/usr/local/api-gateway/lualib make install
 ```

To execute the test issue the following command:
 ```
 make test
 ```

 If you want to run a single test, the following command helps:
 ```
 PATH=/usr/local/sbin:$PATH TEST_NGINX_SERVROOT=`pwd`/target/servroot TEST_NGINX_PORT=1989 prove -I ./test/resources/test-nginx/lib -r ./test/perl/awsv4signature.t
 ```
 This command only executes the test `awsv4signature.t`.

