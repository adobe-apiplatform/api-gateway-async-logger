--[[
  Copyright 2016 Adobe Systems Incorporated. All rights reserved.

  This file is licensed to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR RESPRESENTATIONS OF ANY KIND, either express or implied.  See the License for the specific language governing permissions and limitations under the License.
  ]]

--
-- Logger factory class.

-- User: ddascal
-- Date: 07/03/16
-- Time: 19:49
--

local _M = {_VERSION = "0.7.0" }

-- a table storing initialized logger modules to be reused
-- in the current nginx worker process
_M.loggers = {}

--- Loads a lua gracefully. If the module doesn't exist the exception is caught, logged and the execution continues
-- @param module path to the module to be loaded
--
local function loadrequire(module)
    ngx.log(ngx.DEBUG, "Loading module [" .. tostring(module) .. "]")
    local function requiref(module)
        require(module)
    end

    local res = pcall(requiref, module)
    if not (res) then
        ngx.log(ngx.WARN, "Could not load module [", module, "].")
        return nil
    end
    return require(module)
end

local function _getLogger(name, logger_module, options)
    if (name == nil) then
        ngx.log(ngx.ERR, "Please provide a name for the logger.")
        return
    end

    if ( _M.loggers[name] ~= nil ) then
        ngx.log(ngx.DEBUG, "reusing ", tostring(name), " instance on pid ", tostring(ngx.worker.pid()), " ...")
        return _M.loggers[name]
    end

    if (options == nil) then
        ngx.log(ngx.ERR, "expected options as #3 argument to _getLogger")
        return
    end

    if (options.backend == nil) then
        ngx.log(ngx.ERR, "options.backend is empty. Please set up one.")
        return
    end

    local backend_class = loadrequire(options.backend)
    if (backend_class == nil) then
        ngx.log(ngx.ERR, tostring(options.backend) , " could not be loaded. Did you miss configuring lua_package_path ?")
        return nil
    end

    local logger_class = loadrequire(logger_module)
    if (logger_class == nil) then
        ngx.log(ngx.ERR, tostring(logger_module), " could not be loaded. Did you miss configuring lua_package_path ?")
        return nil
    end

    local logger = logger_class:new(options)

    ngx.log(ngx.INFO, "Starting new ", tostring(logger_module) , " on pid ", tostring(ngx.worker.pid()), " ...")

    _M.loggers[name] = logger
    return logger
end



--- Returns an instance of the moduleName. If the moduleName is initialized alread, it returns the already created instance.
-- This instance should be unique per each nginx worker process
-- @param name A name for this logger.
-- @param logger_module The logger module to use. This module must expose a `new` method for initializing it.
--                   I.e. api-gateway.logger.BufferedAsyncLogger
-- @param options The init options for the logger module
--
function _M:getLogger(name, logger_module, options)
    return _getLogger(name, logger_module, options)
end

return _M

