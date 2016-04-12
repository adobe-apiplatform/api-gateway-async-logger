api-gateway-logger
==================

Performant async logger.

Table of Contents
=================

* [Status](#status)
* [Description](#description)
* [Synopsis](#synopsis)
* [Backend systems](#backend-systems)
* [Developer Guide](#developer-guide)

Status
======

This library is considered production ready.

Description
===========

Lua module to send logs in batches to a backend system.
The logs are sent when one of the following criteria is met:

 * the buffer is full ( `flush_buffer` property) . Default value is 10 logs.
 * it's been more than `flush_interval` seconds since the last flush. Default value is 5 seconds.
 * there are available threads to send logs ( `flush_concurrency` property ). Default value is 3 concurrent threads.
 * throughput rate per second is not exceeded ( `flush_throughput` property ). Default is 1000000. 
   This is a useful setting controlling the rate per second at which the logs are flushed to the backend.
 
So by default the logger sends up to `30` logs simultaneously and if the backend performance is good, it may send more than this per second. 

### Performance
The `BufferedAsyncLogger` modules flushes data asynchronously and non-blocking to a configured backend system.
Data is sent asynchronously using `ngx.timer.at` API which schedules a background non-blocking light thread.
This thread is completely decoupled from the main request.

Depending on the backend you can configure more concurrent threads to flush logs.

> NOTE: Each thread is using a worker connection so make sure to configure nginx with enough worker connections.

Logs could be flushed in parallel in these threads, one batch per thread. 
I.e. if `flush_concurrency` is 10 and `flush_buffer` is 400, this means that 4000 logs can be sent simultaneously to the backend. 

### Failover
When the backend returns a response code other than `200` all the logs are resent with the next flush.
If the backend returns `200` but only some logs have failed, the list with failed logs are resent with the next flush.
It is up to the backend to return the list with failed logs back.

[Back to TOC](#table-of-contents)

Synopsis
========
### Example:

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

[Back to TOC](#table-of-contents)

Backend systems
===============

AWS Kinesis backend
------------------
Sends logs to AWS Kinesis.

HttpLogger backend
------------------
Sends data via POST to an HTTP location

AwsSnsLogger backend
--------------------
Sends data to the AWS SNS, which can then forward the logs to an SQS.

[Back to TOC](#table-of-contents)

Developer guide
===============

## Running the tests

```bash
 make test-docker
```

Test files are located in `test/perl` folder and are based on the `test-nginx` library.
This library is added as a git submodule under `test/resources/test-nginx/` folder, from `https://github.com/agentzh/test-nginx`.

The other libraries such as `Redis`, `test-nginx` would be located in `test/resources/`.
Other files used when running the test are also located in `test/resources`.

 If you want to run a single test edit [docker-compose.yml](test/docker-compose.yml) and replace in `entrypoint` 
 `/tmp/perl` with the actual path to the test ( i.e. `/tmp/perl/my_test.t`)
 
 The complete `entrypoint` config would look like:
```
 entrypoint: ["prove", "-I", "/usr/local/test-nginx-0.24/lib", "-I", "/usr/local/test-nginx-0.24/inc", "-r", "/tmp/perl/my_test.t"]
```
This will only run `my_test.t` test file.

## Running the tests with a native binary
 
 The Makefile also exposes a way to run the tests using a native binary:
 
```
 make test
```
This is intended to be used when the native binary is present and available on `$PATH`.

[Back to TOC](#table-of-contents)
 
