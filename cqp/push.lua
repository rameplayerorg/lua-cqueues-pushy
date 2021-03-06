--[[
Heavily based on https://github.com/sgraf812/push

The MIT License (MIT)

Copyright (c) 2013 Sebastian Graf

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

Coding style changes, along with additional updates and cqueues support
Copyright (c) 2015 Timo Teräs
--]]

local cqueues = require 'cqueues'
local condition = require 'cqueues.condition'
local recorders = { }

local Property = {}
Property.__index = Property

function Property:push_to(pushee, noinit)
	self.__tos[pushee] = pushee
	if noinit ~= true then pushee(self.__value) end
	return function() self.__tos[pushee] = nil end
end

function Property:peek()
	return self.__value
end

function Property:writeproxy(proxy)
	return setmetatable({ }, {
		__tostring = function(t)
			return "(proxied) " .. tostring(self)
		end,
		__index = self,
		__call = function(t, nv)
			if nv ~= nil then
				return self(proxy(nv))
			else
				return self()
			end
		end
	})
end

function Property:__tostring()
	return "Property " .. self.name .. ": " .. tostring(self.__value)
end

function Property:__call(nv)
	if nv ~= nil and nv ~= self.__value then
		local ov = self.__value
		self.__value = nv
		for p in pairs(self.__tos) do p(nv, ov) end
	elseif nv == nil then
		for r in pairs(recorders) do r(self) end
	end
	return self.__value
end

function Property:forceupdate()
	local v = self.__value
	for p in pairs(self.__tos) do p(v, v) end
	return v
end

local P = { action={} }

function P.action.on(trigger, action)
	return function(val, oldval)
		if val == trigger and oldval ~= trigger then
			action()
		end
	end
end

function P.action.threshold(threshold_time, on_short, on_long)
	local cond = condition.new()
	local property = P.property(false)

	property:push_to(function() cond:signal() end)
	cqueues.running():wrap(function()
		while true do
			if property() then
				if cond:wait(threshold_time) then
					-- Short
					if on_short then
						on_short(true)
						on_short(false)
					end
				else
					-- Timeout, long
					if on_long then
						on_long(true)
						while property() do cond:wait() end
						on_long(false)
					end
				end
			else
				cond:wait()
			end
		end
	end)
	return property
end

function P.action.timed(action)
	local down_time = nil
	return function(val)
		local now = cqueues.monotime()
		if val == true then
			down_time = now
		elseif val == false then
			if down_time then action(now-down_time) end
			down_time = nil
		end
	end
end

function P.action.mux(v, name, group, delay)
	local p = P.property(v, name)
	local o = nil

	for i, v in pairs(group) do
		v[1]:push_to(P.action.threshold(delay or 1.0, nil, function() p(i) end))
	end

	p:push_to(function(v)
		local t
		t = group[o]
		if t then t[2](false) end
		t = group[v]
		if t then t[2](true) end
		o = v
	end)
	p:forceupdate()

	return p
end

function P.property(v, name)
	return setmetatable({
		__value = v,
		__tos = { },
		name = name or "<unnamed>",
	}, Property)
end

function P.record_pulls(f)
	local sources = { }
	local function rec(p)
		sources[p] = p
	end
	recorders[rec] = rec
	local status, res = pcall(f)
	recorders[rec] = nil
	if not status then
		return false, res
	else
		return sources, res
	end
end

function P.readonly(self)
	return self:writeproxy(function(nv)
		return error("attempted to set readonly property '" .. tostring(self) .. "' with value " .. tostring(nv))
	end)
end

function P.computed(reader, writer, name)
	local p = P.property(nil, name or "<unnamed>")
	p.__froms = { }

	local function update()
		if not p.__updating then
			p.__updating = true
			local newfroms, res = P.record_pulls(reader)
			if not newfroms then
				p.__updating = false
				error(res)
			end
			for f, remover in pairs(p.__froms) do
				if not newfroms[f] then
					p.__froms[f] = nil
					remover()
				end
			end
			for f in pairs(newfroms) do
				if not p.__froms[f] then
					p.__froms[f] = f:push_to(update)
				end
			end
			p(res)
			p.__updating = false
		end
	end

	update()

	if not writer then
		return P.readonly(p)
	else
		return p:writeproxy(function(nv)
			if p.__updating then return end

			p.__updating = true
			local status, res = pcall(writer, nv)
			p.__updating = false

			return status and res or error(res)
		end)
	end
end

return P
