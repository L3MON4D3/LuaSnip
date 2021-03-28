local ChoiceNode = require'nodes.node'.Node:new()
local util = require'util.util'

local function C(pos, choices)
	return ChoiceNode:new{active = false, pos = pos, choices = choices, type = 4, markers = {}, current_choice = 1, dependents = {}}
end

function ChoiceNode:put_initial()
	for _, node in ipairs(self.choices) do
		node.parent = self.parent
		node.markers = self.markers
		node.next = self
		node.prev = self
		if node.type == 3 then
			node:indent(self.parent.indentstr)
		end
		node.indx = self.indx
	end
	self.inner = self.choices[self.current_choice]
	self.inner:put_initial()
end

function ChoiceNode:input_enter()
	self.parent:enter_node(self.indx)

	self.prev_choice = Luasnip_active_choice
	Luasnip_active_choice = self
	self.active = true
end

function ChoiceNode:input_leave()
	self:update_dependents()
	Luasnip_active_choice = self.prev_choice
	self.active = false
end

function ChoiceNode:set_old_text()
	self.old_text = self:get_text()
	self.inner.old_text = self.old_text
end

function ChoiceNode:has_static_text()
	return self.choices[1]:has_static_text()
end

function ChoiceNode:get_static_text()
	return self.choices[1]:get_static_text()
end

function ChoiceNode:jump_into(dir)
	if self.active then
		self:input_leave()
		if dir == 1 then
			self.next:jump_into(dir)
		else
			self.prev:jump_into(dir)
		end
	else
		self:input_enter()
		self.inner:jump_into(dir)
	end
end

function ChoiceNode:setup_choice_jumps()
end

function ChoiceNode:change_choice(val)
	-- tear down current choice.
	self.choices[self.current_choice]:input_leave()
	self.choices[self.current_choice]:exit()

	-- clear text.
	self.parent:set_text(self, {""})

	local tmp = self.current_choice + val
	if tmp < 1 then
		tmp = #self.choices
	elseif tmp > #self.choices then
		tmp = 1
	end
	self.current_choice = tmp
	self.inner = self.choices[self.current_choice]

	util.move_to_mark(self.markers[1])
	self.inner:put_initial()
	self.inner.old_text = self.inner:get_text()

	self:update_dependents()

	-- Another node may have been entered in update_dependents.
	self.parent:enter_node(self.indx)
	self.inner:jump_into(1)
end

function ChoiceNode:copy()
	local o = vim.deepcopy(self)
	for i, node in ipairs(self.choices) do
		if node.type == 3 or node.type == 4 then
			o.choices[i] = node:copy()
		else
			setmetatable(o.choices[i], getmetatable(node))
		end
	end
	setmetatable(o, getmetatable(self))
	return o
end

return {
	C = C
}
