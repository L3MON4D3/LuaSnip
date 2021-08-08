local DynamicNode = require("luasnip.nodes.node").Node:new()
local util = require("luasnip.util.util")
local Node = require("luasnip.nodes.node").Node
local types = require("luasnip.util.types")

local function D(pos, fn, args, ...)
	return DynamicNode:new({
		pos = pos,
		fn = fn,
		args = util.wrap_value(args),
		type = types.dynamicNode,
		mark = nil,
		user_args = { ... },
		dependents = {},
	})
end

function DynamicNode:get_args()
	local args = {}
	for i, node in ipairs(self.args) do
		args[i] = util.dedent(node:get_text(), self.parent.indentstr)
	end
	args[#args + 1] = self.parent
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

function DynamicNode:put_initial(_) end

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
		self.snip:jump_into(dir)
	end
end

function DynamicNode:update()
	local tmp
	if self.snip then
		self.snip:input_leave()
		-- build new snippet before exiting, markers may be needed for construncting.
		tmp = self.fn(
			self:get_args(),
			self.snip.old_state,
			unpack(self.user_args)
		)
		self.parent:set_text(self, { "" })
		self.snip:exit()
	else
		tmp = self.fn(self:get_args(), nil, unpack(self.user_args))
	end
	self.snip = nil

	-- act as if snip is directly inside parent.
	tmp.parent = self.parent
	tmp.indx = self.indx

	tmp.next = self
	tmp.prev = self

	tmp.env = self.parent.env
	tmp.mark = self.mark
	tmp.dependents = self.dependents

	tmp:indent(self.parent.indentstr)

	self.parent:enter_node(self.indx)
	tmp:put_initial(util.get_ext_position_begin(self.mark.id))
	-- Update, tbh no idea how that could come in handy, but should be done.
	tmp:update()

	tmp:set_old_text()

	self.snip = tmp
end

function DynamicNode:set_mark_rgrav(val_begin, val_end)
	if self.snip then
		self.snip:set_mark_rgrav(val_begin, val_end)
	else
		Node.set_mark_rgrav(self, val_begin, val_end)
	end
end

return {
	D = D,
}
