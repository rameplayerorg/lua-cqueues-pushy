local cq = require 'cqueues'
local tfd = require 'cqp.clib.timerfd'
local posix = require 'posix'
local struct = require 'struct'

local Timer = {}
Timer.__index = Timer

function Timer:pollfd() return self.__fd end
function Timer:events() return "r" end
function Timer:timeout() return nil end

function Timer:read()
	if not self.__armed then
		return nil, "Timer not armed"
	end
	self.__running = true
	while self.__armed and self.__running do
		local data, errmsg, errnum  = posix.read(self.__fd, 8)
		if data == nil then
			if errnum ~= posix.EAGAIN then
				self.__running = nil
				return nil, errmsg, errnum
			end
			cq.poll(self)
		else
			local t = struct.unpack("L", data)
			self.__running = nil
			return math.tointeger(t)
		end
	end
	self.__running = nil
	return nil, "Timer cancelled"
end

function Timer:set(initial, interval, abstime)
	local flags = abstime and (tfd.TFD_TIMER_ABSTIME + tfd.TFD_TIMER_CANCEL_ON_SET) or 0
	self.__armed = true
	return tfd.timerfd_settime(self.__fd, flags, initial, interval or 0)
end

function Timer:get()
	return tfd.timerfd_gettime(self.__fd)
end

function Timer:cancel()
	self.__running = nil
	cq.cancel(self.__fd)
end

function Timer:disarm()
	self.__armed = nil
	self:cancel()
	return tfd.timerfd_settime(self.__fd, 0, 0, 0)
end

function Timer:close()
	if not self.__fd then return end
	self:cancel()
	posix.close(self.__fd)
	self.__fd = nil
end

function Timer:__gc()
	self:close()
end


local M = {}

function M.new(clockid)
	local fd, err = tfd.timerfd_create(clockid or tfd.CLOCK_REALTIME, tfd.TFD_NONBLOCK + tfd.TFD_CLOEXEC)
	if not fd then return nil, err end
	return setmetatable({ __fd = fd}, Timer)
end

return M
