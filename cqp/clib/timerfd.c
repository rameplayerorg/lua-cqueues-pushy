#include <math.h>
#include <errno.h>
#include <string.h>
#include <sys/timerfd.h>

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

static int pusherror(lua_State *L, const char *info)
{
	lua_pushnil(L);
	lua_pushfstring(L, "%s: %s", info, strerror(errno));
	lua_pushinteger(L, errno);
	return 3;
}

static int do_timerfd_create(lua_State *L)
{
	int fd, clockid, flags;

	clockid = luaL_checkinteger(L, 1);
	flags = luaL_checkinteger(L, 2);

	fd = timerfd_create(clockid, flags);
	if (fd < 0) return pusherror(L, "timerfd_create");

	lua_pushinteger(L, fd);
	return 1;
}

static void number_to_timespec(struct timespec *tv, lua_Number val)
{
	lua_Number i, f;
	f = l_mathop(modf)(val, &i);
	tv->tv_sec = i;
	tv->tv_nsec = f * 1000000000;
}

static void push_timespec(lua_State *L, struct timespec *tv)
{
	lua_pushnumber(L, tv->tv_sec + (lua_Number)tv->tv_nsec / 1000000000.);
}

static int do_timerfd_settime(lua_State *L)
{
	struct itimerspec val;
	int fd = luaL_checkinteger(L, 1);
	int flags = luaL_checkinteger(L, 2);

	number_to_timespec(&val.it_value, luaL_checknumber(L, 3));
	number_to_timespec(&val.it_interval, luaL_checknumber(L, 4));
	if (timerfd_settime(fd, flags, &val, &val) < 0)
		return pusherror(L, "timerfd_settime");
	push_timespec(L, &val.it_value);
	push_timespec(L, &val.it_interval);
	return 2;
}

static int do_timerfd_gettime(lua_State *L)
{
	struct itimerspec val;
	int fd = luaL_checkinteger(L, 1);
	if (timerfd_gettime(fd, &val) < 0)
		return pusherror(L, "timerfd_gettime");
	push_timespec(L, &val.it_value);
	push_timespec(L, &val.it_interval);
	return 2;
}

#define definefunc(name) { #name, do_##name }

static const luaL_Reg R[] = {
	definefunc(timerfd_create),
	definefunc(timerfd_settime),
	definefunc(timerfd_gettime),
	{ 0 }
};

static void setuint(lua_State *L, const char *key, unsigned value)
{
	lua_pushinteger(L, value);
	lua_setfield(L, -2, key);
}

#define defineuint(x) setuint(L, #x, x)

LUALIB_API int luaopen_cqp_clib_timerfd(lua_State *L)
{
	lua_newtable(L);
	luaL_setfuncs(L, R, 0);

	defineuint(CLOCK_REALTIME);
	defineuint(CLOCK_MONOTONIC);
	defineuint(CLOCK_BOOTTIME);
	defineuint(CLOCK_REALTIME_ALARM);
	defineuint(CLOCK_BOOTTIME_ALARM);

	defineuint(TFD_NONBLOCK);
	defineuint(TFD_CLOEXEC);
	defineuint(TFD_TIMER_ABSTIME);
	defineuint(TFD_TIMER_CANCEL_ON_SET);

	return 1;
}

