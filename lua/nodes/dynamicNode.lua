local DynamicNode = require'nodes.node'.Node:new()
local util = require'util.util'

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
	self.active = true
end

function DynamicNode:input_leave()
	self:update_dependents()
	self.active = false
end

function DynamicNode:has_static_text()
	return false
end

function DynamicNode:get_static_text()
	return self.snip:get_static_text()
end

function DynamicNode:jump_into(dir)
	if self.active then
		self:input_leave()
		if dir == 1 then
			self.next:jump_into(dir)
		else
			self.prev:jump_into(dir)
		end
	else
		self:input_enter()
		if dir == 1 then
			self.inner:jump_into(dir)
		else
			self.inner:jump_into(dir)
		end
	end
end

function DynamicNode:update()
	if self.snip then
		self.snip:exit()
		self.snip = self.fn(self:get_args(), self.snip.old_state, unpack(self.user_args))
	else
		self.snip = self.fn(self:get_args(), nil, unpack(self.user_args))
	end

	self.inner = self.snip

	self.snip.next = self
	self.snip.prev = self

	self.parent:set_text(self, {""})
	util.move_to_mark(self.markers[1])
	self.snip:indent(self.parent.indentstr)
	self.snip:put_initial()
	self.snip:set_old_text()
end

return {
	D = D
}
