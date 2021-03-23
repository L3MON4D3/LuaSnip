local DynamicNode = require'nodes.node'.Node:new()
local util = require'util'

local function D(pos, fn, args, ...)
	return DynamicNode:new{
		pos = pos,
		fn = fn,
		args = args,
		type = 5,
		markers = {},
		user_args = {...}
	}
end

function DynamicNode:get_args()
	local args = {}
	for i, node in ipairs(self.args) do
		args[i] = node:get_text()
	end
	return args
end

function DynamicNode:input_enter()
	self.old_text = self:get_text()
	self.snip:input_enter()
end

function DynamicNode:input_leave()
	if not util.multiline_equal(self.old_text, self:get_text()) then
		self:update_dependents()
	end
	self.snip:input_leave()
end

function DynamicNode:has_static_text()
	return false
end

function DynamicNode:get_static_text()
	return self.snip:get_static_text()
end

function DynamicNode:copy()
	local o = {pos = self.pos, fn = self.fn, args = self.args, type = 5, markers = self.markers, user_args = self.user_args}
	o.snip = self.snip:copy()
	return o
end

function DynamicNode:update()
	local snip
	if self.snip then
		snip = self.fn(self:get_args(), self.snip.old_state, unpack(self.user_args))
		self.snip:exit()
	else
		snip = self.fn(self:get_args(), nil, unpack(self.user_args))
	end
	self.snip = snip

	self.parent:set_text(self, {""})
	util.move_to_mark(self.markers[1])
	self.snip:put_initial()
end

return {
	D = D
}
