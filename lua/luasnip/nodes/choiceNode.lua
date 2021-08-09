local node = require("luasnip.nodes.node").Node
local ChoiceNode = node:new()
local util = require("luasnip.util.util")
local types = require("luasnip.util.types")
local mark = require("luasnip.util.mark").mark

local function C(pos, choices)
	return ChoiceNode:new({
		active = false,
		pos = pos,
		choices = choices,
		type = types.choiceNode,
		mark = nil,
		current_choice = 1,
		dependents = {},
	})
end

function ChoiceNode:put_initial(pos)
	for _, node in ipairs(self.choices) do
		node.parent = self.parent
		node.next = self
		node.prev = self
		node.dependents = self.dependents
		if node.type == types.snippetNode then
			node:indent(self.parent.indentstr)
			node.env = self.parent.env
			node.ext_opts = self.parent.ext_opts
		end
		node.indx = self.indx
		node.pos = self.pos
		-- if function- or dynamicNode, dependents may need to be replaced with
		-- actual nodes, until here dependents may only contain indices of nodes.
		if
			node.type == types.functionNode
			or node.type == types.dynamicNode
		then
			self.parent:populate_args(node)
		end
	end
	self.inner = self.choices[self.current_choice]

	local old_pos = vim.deepcopy(pos)

	self.inner:put_initial(pos)

	local mark_opts = vim.tbl_extend("keep", {
		right_gravity = not (old_pos[1] == pos[1] and old_pos[2] == pos[2]),
		end_right_gravity = false,
	}, self.parent.ext_opts[self.inner.type].passive)

	self.inner.mark = mark(old_pos, pos, mark_opts)
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

function ChoiceNode:update()
	self.inner:update()
end

function ChoiceNode:setup_choice_jumps() end

function ChoiceNode:change_choice(val)
	-- tear down current choice.
	self.inner:input_leave()
	-- clear text.
	self.parent:set_text(self, { "" })

	self.inner:exit()

	local tmp = self.current_choice + val
	if tmp < 1 then
		tmp = #self.choices
	elseif tmp > #self.choices then
		tmp = 1
	end
	self.current_choice = tmp
	self.inner = self.choices[self.current_choice]

	self.inner.mark = self.mark:copy_pos_gravs(
		vim.deepcopy(self.parent.ext_opts[self.inner.type].passive)
	)
	self.inner:put_initial(util.get_ext_position_begin(self.mark.id))
	self.inner:update()
	self.inner.old_text = self.inner:get_text()

	self:update_dependents()

	-- Another node may have been entered in update_dependents.
	self.parent:enter_node(self.indx)
	self.inner:jump_into(1)
end

function ChoiceNode:copy()
	local o = vim.deepcopy(self)
	for i, node in ipairs(self.choices) do
		if node.type == types.snippetNode or node.type == types.choiceNode then
			o.choices[i] = node:copy()
		else
			setmetatable(o.choices[i], getmetatable(node))
		end
	end
	setmetatable(o, getmetatable(self))
	return o
end

-- val_begin/end may be nil, in this case that gravity won't be changed.
function ChoiceNode:set_mark_rgrav(rgrav_beg, rgrav_end)
	node.set_mark_rgrav(self, rgrav_beg, rgrav_end)
	self.inner:set_mark_rgrav(rgrav_beg, rgrav_end)
end

return {
	C = C,
}
