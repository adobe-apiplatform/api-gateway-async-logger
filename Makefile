# NOTE: Every line in a recipe must begin with a tab character.
BUILD_DIR ?= target

PREFIX ?=          /usr/local
LUA_INCLUDE_DIR ?= $(PREFIX)/include
LUA_LIB_DIR ?=     $(PREFIX)/lib/lua/$(LUA_VERSION)
INSTALL ?= install

.PHONY: all clean test install

all: ;

install: all
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/logger/
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/aws/
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/resty/hmac.lua
	$(INSTALL) src/lua/api-gateway/logger/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/logger/
	$(INSTALL) src/lua/api-gateway/aws/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/aws/
	$(INSTALL) src/lua/api-gateway/resty/hmac.lua $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/resty/hmac.lua

test:
	echo "running tests ..."
#	cp -r test/resources/api-gateway $(BUILD_DIR)
	PATH=/usr/local/sbin:$$PATH TEST_NGINX_SERVROOT=`pwd`/$(BUILD_DIR)/servroot TEST_NGINX_PORT=1989 prove -I ./test/resources/test-nginx/lib -r ./test/perl

package:
	git archive --format=tar --prefix=api-gateway-logger-0.1/ -o api-gateway-logger-0.1.tar.gz -v HEAD

clean: all
	rm -rf $(BUILD_DIR)/servroot