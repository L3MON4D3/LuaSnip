local ChoiceNode = require'nodes.node'.Node:new()
local util = require'util'

local function C(pos, choices)
	return ChoiceNode:new{pos = pos, choices = choices, type = 4, markers = {}, current_choice = 1}
end

function ChoiceNode:put_initial()
	for _, node in ipairs(self.choices) do
		node.markers = self.markers
		node.markers = self.markers
		if node.type == 3 then
			node:indent(self.parent.indentstr)
		end
	end
	self.choices[1]:put_initial()
end

function ChoiceNode:input_enter()
	self.old_text = self:get_text()
	self.choices[self.current_choice]:input_enter()
	Luasnip_active_choice = self
end

function ChoiceNode:input_leave()
	if not util.multiline_equal(self.old_text, self:get_text()) then
		self:update_dependents()
	end
	self.choices[self.current_choice]:input_leave()
	Luasnip_active_choice = nil
end

function ChoiceNode:has_static_text()
	return self.choices[1]:has_static_text()
end

function ChoiceNode:get_static_text()
	return self.choices[1]:get_static_text()
end

function ChoiceNode:change_choice(val)
	-- tear down current choice.
	self.choices[self.current_choice]:input_leave()
	self.choices[self.current_choice]:exit()

	-- clear text.
	Luasnip_active_snippet:set_text(self, {""})
	util.move_to_mark(self.markers[1])
	local tmp = self.current_choice + val
	if tmp < 1 then
		tmp = #self.choices
	elseif tmp > #self.choices then
		tmp = 1
	end
	self.current_choice = tmp
	self.choices[self.current_choice]:put_initial()
	util.move_to_mark(self.markers[1])
	self.choices[self.current_choice]:input_enter()
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
