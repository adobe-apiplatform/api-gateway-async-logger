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
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/logger/backend
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/zmq/
	$(INSTALL) src/lua/api-gateway/logger/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/logger/
	$(INSTALL) src/lua/api-gateway/logger/backend/* $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/logger/backend/
	$(INSTALL) src/lua/api-gateway/zmq/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/zmq/

test:
	echo "updating git submodules ..."
	if [ ! -d "test/resources/test-nginx/lib" ]; then	git submodule update --init --recursive; fi
	echo "running tests ..."
	mkdir  -p $(BUILD_DIR)
	mkdir  -p $(BUILD_DIR)/test-logs
	rm -f $(BUILD_DIR)/test-logs/*
#	cp -r test/resources/api-gateway $(BUILD_DIR)
	TEST_NGINX_AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" TEST_NGINX_AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" TEST_NGINX_AWS_SECURITY_TOKEN="${AWS_SECURITY_TOKEN}"  \
	    PATH=/usr/local/sbin:$$PATH \
	    TEST_NGINX_SERVROOT=`pwd`/$(BUILD_DIR)/servroot \
	    TEST_NGINX_PORT=1989 \
	    prove -I ./test/resources/test-nginx/lib -I ./test/resources/test-nginx/inc -r ./test/perl

package:
	git tag -a v0.7.2 -m 'release-0.7.2'
	git push origin v0.7.2
	git archive --format=tar --prefix=api-gateway-logger-0.7.2/ -o api-gateway-logger-0.7.2.tar.gz -v HEAD

clean: all
	rm -rf $(BUILD_DIR)/servroot