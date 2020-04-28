LUA_VERSION = 5.2
LUA = lua$(LUA_VERSION)

ALL_LUA := $(wildcard cqp/*.lua cqp/*/*.lua)
ALL_C := cqp/clib/modem.c cqp/clib/i2c.c cqp/clib/timerfd.c

all: cqp.so

cqp.so: $(ALL_C)
	gcc $(CFLAGS) -fPIC $(shell pkg-config --cflags $(LUA)) -shared $^ -o $@ $(shell pkg-config --libs $(LUA))

install: all
	for f in $(ALL_LUA); do \
		install -D -m644 $$f $(DESTDIR)/usr/share/lua/$(LUA_VERSION)/$$f ; \
	done
	install -D -m644 cqp.so $(DESTDIR)/usr/lib/lua/$(LUA_VERSION)/cqp.so ; \

clean:
	rm $(ALL_SO)
