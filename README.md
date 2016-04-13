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
Backend implementation for sending logs to AWS Kinesis. This guide walks you through a few steps for configuring it.
 This is not the only setup but it's performant and it's a great way to start with.

In NGINX conf define the following variables:

 * `aws_region` - the AWS region where the kinesis stream is created
 * `kinesis_stream_name` - the name of the kinesis stream

Make sure to define 2 shared dictionaries:

* `lua_shared_dict stats_kinesis 16m;` - dictionary used to buffer the logs in memory 
* `lua_shared_dict aws_credentials 1m;` - dictionary used to cache any IAM and STS credentials 

Then in the `log_by_lua` configure the logger to send the information:
```lua
local cjson = require "cjson"
local logger_factory = require "api-gateway.logger.factory"

local function get_logger_configuration()
    local logger_module = "api-gateway.logger.BufferedAsyncLogger"
    local logger_opts = {
        flush_length = 500,          -- http://docs.aws.amazon.com/kinesis/latest/APIReference/API_PutRecords.html - 500 is max
        flush_interval = 5,          -- interval in seconds to flush regardless if the buffer is full or not
        flush_concurrency = 16,      -- max parallel threads used for sending logs
        flush_throughput = 10000,     -- max logs / SECOND that can be sent to the Kinesis backend
        sharedDict = "stats_kinesis", -- dict for caching the logs
        backend = "api-gateway.logger.backend.AwsKinesisLogger",
        backend_opts = {
            aws_region = ngx.var.aws_region or "us-east-1",
            kinesis_stream_name = ngx.var.kinesis_stream_name or "api-gateway-stream",
            aws_credentials = {
                provider = "api-gateway.aws.AWSIAMCredentials",
                shared_cache_dict = "aws_credentials"  -- dict for caching STS and IAM credentials
            }
        },
        callback = function(status)
            -- capture or log information about each flush
            -- status.logs_sent    - how many logs have been flushed successfully
            -- status.logs_failed  - how many logs failed to be sent
            -- status.backend_response_code - HTTP Status code returned by Kinesis
            -- status.threads_running - how many parallel threads are active
            -- status.threads_pending - how many threads are waiting to be executed
        end
    }
    return logger_module, logger_opts
end    

local function get_logger(name)
    -- try to reuse an existing logger instance for each worker process
    if (logger_factory:hasLogger(name)) then
        return logger_factory:getLogger(name)
    end
    
    -- create a new logger instance
    local logger_module , logger_opts = get_logger_configuration()
    return logger_factory:getLogger(name, logger_module, logger_opts)
end
    
local kinesis_logger = get_logger("kinesis-logger")

local partition_key = ngx.utctime() .."-".. math.random(ngx.now() * 1000)
local kinesis_data = {}

-- add any information you want to capture
kinesis_data["http_referer"] = ngx.var.http_referer
kinesis_data["user_agent"] = ngx.var.http_user_agent
kinesis_data["hostname"] = ngx.var.hostname
kinesis_data["http_host"] = ngx.var.host

-- at the end log the message
kinesis_logger:logMetrics( partition_key, cjson.encode(kinesis_data))
```

If you want to use STS Credentials instead of IAM Credentials with the Kinesis Logger then configure the `backend_opts.aws_credentials` as follows:
```lua
aws_credentials = {
    provider = "api-gateway.aws.AWSSTSCredentials",
    role_ARN = "arn:aws:iam::" .. ngx.var.kinesis_aws_account .. ":role/" .. ngx.var.kinesis_iam_role,
    role_session_name = "kinesis-logger-session",
    shared_cache_dict = "aws_credentials"  -- dict for caching STS and IAM credentials
}
```

Make sure to also configure the NGINX variables:

* `kinesis_aws_account` - the AWS Account where the kinesis stream is configured
* `kinesis_iam_role` - the role to be assumed in order to send the logs to kinesis

>INFO: If you send the logs into the same account where NGINX runs you don't need to configure any STS Credentials, but you can use IAM Credentials. 

For more information about `AWSSTSCredentials` configuration see [the documentation](https://github.com/adobe-apiplatform/api-gateway-aws#sts-credentials).

If you can't use IAM Credentials nor STS Credentials, then you can still send logs to Kinesis by configuring AWS with static `access_key` and `secret`.
 These are not as secure as IAM/STS but are working for non-AWS deployments:

```lua
aws_credentials = {
    provider = "api-gateway.aws.AWSBasicCredentials",
    access_key = "replace-me",
    secret_key = "replace-me"
}
```

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
 
