local cqueues = require 'cqueues'
local condition = require 'cqueues.condition'
local push = require 'cqp.push'
local http = require 'cqp.http'

local PanasonicAW = {}
PanasonicAW.__index = PanasonicAW

local sync=2
local global_seq=1

local function limit(val, _min, _max)
	if val < _min then return _min end
	if val > _max then return _max end
	return val
end

local function scale(val)
	return limit(50+math.floor(49*val), 1, 99)
end

function PanasonicAW:init(ip)
	self.__ip = ip
	self.__cmdold = {}
	self.__cmdqueue = {}
	self.__cmdcond = condition.new()
	self.__pan = 50
	self.__tilt = 50

	self.power = push.property(true, ("AW %s - Power"):format(self.__ip))
	self.tally = push.property(false, ("AW %s - Tally"):format(self.__ip))

	self.pan = push.property(0, ("AW %s - Pan"):format(self.__ip))
	self.tilt = push.property(0, ("AW %s - Tilt"):format(self.__ip))
	self.zoom = push.property(0, ("AW %s - Zoom"):format(self.__ip))

	self.power:push_to(function(val, oval) self:aw_ptz(true, "O", "%d", val and 1 or 0) end)
	self.tally:push_to(function(val, oval) print("Tally", val, oval) self:aw_ptz(true, "DA", "%d", val and 1 or 0) end)
	self.pan:push_to(function(val)  self.__pan  = scale(val) self:aw_ptz(false, "PTS", "%02d%02d", self.__pan, self.__tilt) end)
	self.tilt:push_to(function(val) self.__tilt = scale(val) self:aw_ptz(false, "PTS", "%02d%02d", self.__pan, self.__tilt) end)
	self.zoom:push_to(function(val) self.__zoom = scale(val) self:aw_ptz(false, "Z", "%02d", self.__zoom) end)
end

function PanasonicAW:aw_ptz(force, cmd, fmt, ...)
	local val = fmt and fmt:format(...) or ""
	local seq = cmd
	if force or self.__cmdold[cmd] ~= val then
		local cmdtbl = { cmd = cmd, val = val }
		if force == sync then
			cmdtbl.cond = condition.new()
			seq = global_seq
			global_seq = global_seq + 1
		end
		self.__cmdqueue[seq] = cmdtbl
		self.__cmdold[cmd] = val
		self.__cmdcond:signal(1)
		if force == sync then
			cmdtbl.cond:wait()
			return cmdtbl.res
		end
	end
end

function PanasonicAW:goto_preset(no) self:aw_ptz(true, "R", "%02d", no-1) end
function PanasonicAW:save_preset(no) self:aw_ptz(true, "M", "%02d", no-1) end

function PanasonicAW:get_abs()
	local pos, zoom
	pos = self:aw_ptz(sync, "APC")
	zoom = self:aw_ptz(sync, "GZ")
	if type(pos)  == "string" and string.len(pos)  == 11 and
	   type(zoom) == "string" and string.len(zoom) == 5 then
		return pos:sub(4) .. zoom:sub(3)
	end
	return nil
end

function PanasonicAW:goto_abs(pos)
	if #pos == 11 then
		self:aw_ptz(false, "APC", "%08s", pos:sub(1, 8))
		self:aw_ptz(false, "AXZ", "%03s", pos:sub(9, 11))
		return pos
	end
	return nil
end

function PanasonicAW:main()
	while true do
		local sleep = true
		for seq, val in pairs(self.__cmdqueue) do
			local uri = ("/cgi-bin/aw_ptz?cmd=%%23%s%s&res=1"):format(val.cmd, val.val)
			local status, res = http.get(self.__ip, 80, uri)
			print("Posting", self.__ip, uri, status)
			if (status == 200 or val.cond) and self.__cmdqueue[seq] == val then
				-- ACK command from queue (unless we got new already)
				self.__cmdqueue[seq] = nil
			elseif status == nil then
				-- HTTP failed, throttle resend
				cqueues.sleep(1.0)
			end
			if val.cond then
				val.res = res
				val.cond:signal()
			end

			sleep = false
			break
		end
		if sleep then self.__cmdcond:wait() end
	end
end

local M = {}

function M.new(ip)
	local o = setmetatable({}, PanasonicAW)
	o:init(ip)
	cqueues.running():wrap(function() o:main() end)
	return o
end

return M
