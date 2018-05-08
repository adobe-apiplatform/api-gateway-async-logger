package="api-gateway-async-logger"
version="1.0.1-1"
local function make_plat(plat)
    return { modules = {
        ["api-gateway.logger.AsyncLogger"] = "src/lua/api-gateway/logger/AsyncLogger.lua",
        ["api-gateway.logger.BufferedAsyncLogger"] = "src/lua/api-gateway/logger/BufferedAsyncLogger.lua",
        ["api-gateway.logger.factory"] = "src/lua/api-gateway/logger/factory.lua",
        ["api-gateway.logger.http"] = "src/lua/api-gateway/logger/http.lua",
        ["api-gateway.logger.url"] = "src/lua/api-gateway/logger/url.lua",
        ["api-gateway.logger.backend.AwsKinesisLogger"] = "src/lua/api-gateway/logger/backend/AwsKinesisLogger.lua",
        ["api-gateway.logger.backend.AwsSnsLogger"] = "src/lua/api-gateway/logger/backend/AwsSnsLogger.lua",
        ["api-gateway.logger.backend.HttpLogger"] = "src/lua/api-gateway/logger/backend/HttpLogger.lua"
    } }
end
source = {
    url = "git://github.com/adobe-apiplatform/api-gateway-async-logger.git",
    tag = "1.0.1"
}
description = {
    summary = "Lua Module providing an async-logger framework in the API Gateway.",
    license = "MIT"
}
dependencies = {
    "lua > 5.1"
}
build = {
    type = "builtin",
    platforms = {
        unix = make_plat("unix"),
        macosx = make_plat("macosx"),
        haiku = make_plat("haiku"),
        win32 = make_plat("win32"),
        mingw32 = make_plat("mingw32")
    }
}