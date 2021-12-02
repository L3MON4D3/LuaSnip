local Node = require("luasnip.nodes.node").Node
local ChoiceNode = Node:new()
local util = require("luasnip.util.util")
local conf = require("luasnip.config")
local types = require("luasnip.util.types")
local events = require("luasnip.util.events")
local mark = require("luasnip.util.mark").mark
local session = require("luasnip.session")
local sNode = require("luasnip.nodes.snippet").SN

function ChoiceNode:init_nodes()
	for i, choice in ipairs(self.choices) do
		-- setup jumps
		choice.next = self
		choice.prev = self

		-- forward values for unknown keys from choiceNode.
		choice.choice = self
		local node_mt = getmetatable(choice)
		setmetatable(choice, {
			__index = function(node, key)
				return node_mt[key] or node.choice[key]
			end,
		})

		-- replace nodes' original update_dependents with function that also
		-- calls this choiceNodes' update_dependents.
		--
		-- cannot define as `function node:update_dependents()` as _this_
		-- choiceNode would be `self`.
		-- Also rely on node.choice, as using `self` there wouldn't be caught
		-- by copy and the wrong node would be updated.
		choice.update_dependents = function(node)
			node:_update_dependents()
			node.choice:update_dependents()
		end

		choice.next_choice = self.choices[i + 1]
		choice.prev_choice = self.choices[i - 1]
	end
	self.choices[#self.choices].next_choice = self.choices[1]
	self.choices[1].prev_choice = self.choices[#self.choices]

	self.active_choice = self.choices[1]
end

local function C(pos, choices, opts)
	opts = opts or {}
	if opts.restore_cursor == nil then
		-- disable by default, can affect performance.
		opts.restore_cursor = false
	end

	-- allow passing table of nodes in choices, will be turned into a
	-- snippetNode.
	for indx, choice in ipairs(choices) do
		if not getmetatable(choice) then
			-- is a normal table, not a node.
			choices[indx] = sNode(nil, choice)
		end
	end

	local c = ChoiceNode:new({
		active = false,
		pos = pos,
		choices = choices,
		type = types.choiceNode,
		mark = nil,
		dependents = {},
		-- default to true.
		restore_cursor = opts.restore_cursor,
	})
	c:init_nodes()
	return c
end

function ChoiceNode:subsnip_init()
	for _, node in ipairs(self.choices) do
		if node.type == types.snippetNode then
			node.env = self.parent.env
			node.ext_opts = util.increase_ext_prio(
				vim.deepcopy(self.parent.ext_opts),
				conf.config.ext_prio_increase
			)
			node.snippet = self.parent.snippet
		end
		node:subsnip_init()
	end
end

function ChoiceNode:put_initial(pos)
	local old_pos = vim.deepcopy(pos)

	self.active_choice:put_initial(pos)

	local mark_opts = vim.tbl_extend("keep", {
		right_gravity = false,
		end_right_gravity = false,
	}, self.parent.ext_opts[self.active_choice.type].passive)

	self.active_choice.mark = mark(old_pos, pos, mark_opts)
end

function ChoiceNode:populate_argnodes()
	for _, node in ipairs(self.choices) do
		-- if function- or dynamicNode, dependents may need to be replaced with
		-- actual nodes, until here dependents may only contain indices of nodes.
		-- stylua: ignore
		if
			node.type == types.functionNode
			or node.type == types.dynamicNode
		then
			self.parent:populate_args(node)
		end
	end
end

function ChoiceNode:indent(indentstr)
	for _, node in ipairs(self.choices) do
		node:indent(indentstr)
	end
end

function ChoiceNode:expand_tabs(tabwidth)
	for _, node in ipairs(self.choices) do
		node:expand_tabs(tabwidth)
	end
end

function ChoiceNode:input_enter()
	self.mark:update_opts(self.parent.ext_opts[self.type].active)
	self.parent:enter_node(self.indx)

	self.prev_choice_node = session.active_choice_node
	session.active_choice_node = self
	self.active = true

	self:event(events.enter)
end

function ChoiceNode:input_leave()
	self:event(events.leave)

	self.mark:update_opts(self.parent.ext_opts[self.type].passive)
	self:update_dependents()
	session.active_choice_node = self.prev_choice_node
	self.active = false
end

function ChoiceNode:set_old_text()
	self.old_text = self:get_text()
	self.active_choice.old_text = self.old_text
end

function ChoiceNode:get_static_text()
	return self.choices[1]:get_static_text()
end

function ChoiceNode:get_docstring()
	return util.string_wrap(
		self.choices[1]:get_docstring(),
		rawget(self, "pos")
	)
end

function ChoiceNode:jump_into(dir, no_move)
	if self.active then
		self:input_leave()
		if dir == 1 then
			return self.next:jump_into(dir, no_move)
		else
			return self.prev:jump_into(dir, no_move)
		end
	else
		self:input_enter()
		return self.active_choice:jump_into(dir, no_move)
	end
end

function ChoiceNode:update()
	self.active_choice:update()
end

function ChoiceNode:update_restore()
	self.active_choice:update_restore()
end

function ChoiceNode:setup_choice_jumps() end

function ChoiceNode:find_node(predicate)
	if self.active_choice then
		if predicate(self.active_choice) then
			return self.active_choice
		else
			return self.active_choice:find_node(predicate)
		end
	end
	return nil
end

-- used to uniquely identify this change-choice-action.
local change_choice_id = 0

function ChoiceNode:change_choice(dir, current_node)
	change_choice_id = change_choice_id + 1
	-- to uniquely identify this node later (storing the pointer isn't enough
	-- because this is supposed to work with restoreNodes, which are copied).
	current_node.change_choice_id = change_choice_id

	local insert_pre_cc = vim.fn.mode() == "i"
	-- is byte-indexed! Doesn't matter here, but important to be aware of.
	local cursor_pos_pre_relative = util.pos_sub(
		util.get_cursor_0ind(),
		current_node.mark:pos_begin_raw()
	)

	self.active_choice:store()
	-- tear down current choice.
	self.active_choice:input_leave()
	self.active_choice:exit()

	-- store in old_choice, active_choice has to be disabled to prevent reading
	-- from cleared mark in set_mark_rgrav (which will be called in
	-- parent:set_text(self,...) a few lines below).
	local old_choice = self.active_choice
	self.active_choice = nil

	-- clear text.
	self.parent:set_text(self, { "" })

	-- stylua: ignore
	self.active_choice = dir == 1 and old_choice.next_choice
	                               or old_choice.prev_choice

	self.active_choice.mark = self.mark:copy_pos_gravs(
		vim.deepcopy(self.parent.ext_opts[self.active_choice.type].passive)
	)
	self.active_choice:put_initial(self.mark:pos_begin_raw())
	self.active_choice:update_restore()
	self.active_choice.old_text = self.active_choice:get_text()

	self:update_dependents()

	-- Another node may have been entered in update_dependents.
	self.parent:enter_node(self.indx)
	self:event(events.change_choice)

	if self.restore_cursor then
		local target_node = self:find_node(function(test_node)
			return test_node.change_choice_id == change_choice_id
		end)

		if target_node then
			-- the node that the cursor was in when changeChoice was called exists
			-- in the active choice! jump_into it!
			--
			-- if in INSERT before change_choice, don't actually move into the node.
			-- The new cursor will be set to the actual edit-position later.
			local jump_node = self.active_choice:jump_into(1, insert_pre_cc)

			local jumps = 1
			while jump_node ~= target_node do
				jump_node = jump_node:jump_from(1, insert_pre_cc)

				-- just for testing...
				if jumps > 1000 then
					print("FAIL! Too many jumps!!")
					return self.active_choice:jump_into(1, insert_pre_cc)
				end
				jumps = jumps + 1
			end
			if insert_pre_cc then
				util.set_cursor_0ind(
					util.pos_add(
						target_node.mark:pos_begin_raw(),
						cursor_pos_pre_relative
					)
				)
			end
			return jump_node
		end
	end

	return self.active_choice:jump_into(1)
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

function ChoiceNode:exit()
	self.active_choice:exit()
	self.mark:clear()
	if self.active then
		session.active_choice_node = self.prev_choice_node
	end
	self.active = false
end

-- val_begin/end may be nil, in this case that gravity won't be changed.
function ChoiceNode:set_mark_rgrav(rgrav_beg, rgrav_end)
	Node.set_mark_rgrav(self, rgrav_beg, rgrav_end)
	-- may be set to temporarily in change_choice.
	if self.active_choice then
		self.active_choice:set_mark_rgrav(rgrav_beg, rgrav_end)
	end
end

function ChoiceNode:set_ext_opts(name)
	self.mark:update_opts(self.parent.ext_opts[self.type][name])
	self.active_choice:set_ext_opts(name)
end

function ChoiceNode:store()
	self.active_choice:store()
end

return {
	C = C,
}
