local Node = require("luasnip.nodes.node")
local InsertNode = Node.Node:new()
local ExitNode = InsertNode:new()
local util = require("luasnip.util.util")
local node_util = require("luasnip.nodes.util")
local types = require("luasnip.util.types")
local events = require("luasnip.util.events")
local extend_decorator = require("luasnip.util.extend_decorator")

local function I(pos, static_text, opts)
	static_text = util.to_string_table(static_text)

	if pos == 0 then
		return ExitNode:new({
			pos = pos,
			static_text = static_text,
			mark = nil,
			dependents = {},
			type = types.exitNode,
			-- will only be needed for 0-node, -1-node isn't set with this.
			ext_gravities_active = { false, false },
		}, opts)
	else
		return InsertNode:new({
			pos = pos,
			static_text = static_text,
			mark = nil,
			dependents = {},
			type = types.insertNode,
			inner_active = false,
		}, opts)
	end
end
extend_decorator.register(I, { arg_indx = 3 })

function ExitNode:input_enter(no_move, dry_run)
	if dry_run then
		return
	end

	-- Don't enter node for -1-node, it isn't in the node-table.
	if self.pos == 0 then
		InsertNode.input_enter(self, no_move, dry_run)
	else
		-- -1-node:
		-- set rgrav true on left side of snippet. Text inserted now pushes the
		-- snippet, and is not contained in it.
		local begin_pos = self.mark:pos_begin_raw()
		self.parent:subtree_set_pos_rgrav(begin_pos, 1, true)

		if not no_move then
			if vim.fn.mode() == "i" then
				util.insert_move_on(begin_pos)
			else
				vim.api.nvim_feedkeys(
					vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
					"n",
					true
				)
				util.normal_move_on_insert(begin_pos)
			end
		end

		self:event(events.enter)
	end
end

function ExitNode:focus()
	local lrgrav, rrgrav
	local snippet = self.parent
	-- if last of first node of the snippet, make inserted text move out of snippet.
	if snippet.nodes[#snippet.nodes] == self then
		lrgrav = false
		rrgrav = false
	elseif snippet.nodes[1] == self then
		lrgrav = true
		rrgrav = true
	else
		lrgrav = false
		rrgrav = true
	end

	Node.focus_node(self, lrgrav, rrgrav)
end

function ExitNode:input_leave(no_move, dry_run)
	if dry_run then
		return
	end

	if self.pos == 0 then
		InsertNode.input_leave(self, no_move, dry_run)
	else
		self:event(events.leave)
	end
end

function ExitNode:_update_dependents() end
function ExitNode:update_dependents() end
function ExitNode:update_all_dependents() end

function ExitNode:_update_dependents_static() end
function ExitNode:update_dependents_static() end
function ExitNode:update_all_dependents_static() end
function ExitNode:is_interactive()
	return true
end

function InsertNode:input_enter(no_move, dry_run)
	if dry_run then
		return
	end

	self.visited = true
	self.mark:update_opts(self.ext_opts.active)

	-- no_move only prevents moving the cursor, but the active node should
	-- still be focused.
	self:focus()

	if not no_move then
		-- SELECT snippet text only when there is text to select (more oft than not there isnt).
		local mark_begin_pos, mark_end_pos = self.mark:pos_begin_end_raw()
		if not util.pos_equal(mark_begin_pos, mark_end_pos) then
			util.any_select(mark_begin_pos, mark_end_pos)
		else
			-- if current and target mode is INSERT, there's no reason to leave it.
			if vim.fn.mode() == "i" then
				util.insert_move_on(mark_begin_pos)
			else
				-- mode might be VISUAL or something else, but <Esc> always leads to normal.
				vim.api.nvim_feedkeys(
					vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
					"n",
					true
				)
				util.normal_move_on_insert(mark_begin_pos)
			end
		end
	end

	self:event(events.enter)
end

-- only necessary for insertNodes, inner_active (unlike `active`) does not occur
-- in other nodes.
-- Since insertNodes don't have `active`, we can use the dry_run.active-field
-- for this.
function InsertNode:init_dry_run_inner_active(dry_run)
	if dry_run and dry_run.active[self] == nil then
		dry_run.active[self] = self.inner_active
	end
end
function InsertNode:is_inner_active(dry_run)
	return (not dry_run and self.inner_active)
		or (dry_run and dry_run.active[self])
end

function InsertNode:jump_into(dir, no_move, dry_run)
	self:init_dry_run_inner_active(dry_run)

	if self:is_inner_active(dry_run) then
		if dir == 1 then
			if self.next then
				self:input_leave_children(dry_run)
				self:input_leave(no_move, dry_run)
				return self.next:jump_into(dir, no_move, dry_run)
			else
				return nil
			end
		else
			if self.prev then
				self:input_leave_children(dry_run)
				self:input_leave(no_move, dry_run)
				return self.prev:jump_into(dir, no_move, dry_run)
			else
				return nil
			end
		end
	else
		self:input_enter(no_move, dry_run)
		return self
	end
end

function ExitNode:jump_from(dir, no_move, dry_run)
	self:init_dry_run_inner_active(dry_run)

	local next_node = util.ternary(dir == 1, self.next, self.prev)
	local next_inner_node =
		util.ternary(dir == 1, self.inner_first, self.inner_last)

	if next_inner_node then
		self:input_enter_children(dry_run)
		return next_inner_node:jump_into(dir, no_move, dry_run)
	else
		if next_node then
			local next_node_dry_run = { active = {} }
			-- don't have to `init_dry_run_inner_active` since this node does
			-- not have children active if jump_from is called.

			-- true: don't move
			local target_node =
				next_node:jump_into(dir, true, next_node_dry_run)
			-- if there is no node that can serve as jump-target, just remain
			-- here.
			-- Regular insertNodes don't have to handle this, since there is
			-- always an exitNode or another insertNode at their endpoints.
			if not target_node then
				return self
			end

			self:input_leave(no_move, dry_run)
			return next_node:jump_into(dir, no_move, dry_run) or self
		else
			return self
		end
	end
end

function InsertNode:jump_from(dir, no_move, dry_run)
	self:init_dry_run_inner_active(dry_run)

	local next_node = util.ternary(dir == 1, self.next, self.prev)
	local next_inner_node =
		util.ternary(dir == 1, self.inner_first, self.inner_last)

	if next_inner_node then
		self:input_enter_children(dry_run)
		return next_inner_node:jump_into(dir, no_move, dry_run)
	else
		if next_node then
			self:input_leave(no_move, dry_run)
			return next_node:jump_into(dir, no_move, dry_run)
		end
	end
end

function InsertNode:input_enter_children(dry_run)
	if dry_run then
		dry_run.active[self] = true
	else
		self.inner_active = true
	end
end
function InsertNode:input_leave_children(dry_run)
	if dry_run then
		dry_run.active[self] = false
	else
		self.inner_active = false
	end
end

function InsertNode:input_leave(_, dry_run)
	if dry_run then
		return
	end

	self:event(events.leave)

	self:update_dependents()
	self.mark:update_opts(self:get_passive_ext_opts())
end

function InsertNode:exit()
	if self.inner_first then
		self.inner_first:exit()
	end
	self.visible = false
	self.inner_first = nil
	self.inner_last = nil
	self.inner_active = false
	self.mark:clear()
end

function InsertNode:get_docstring()
	-- copy as to not in-place-modify static text.
	return util.string_wrap(self.static_text, rawget(self, "pos"))
end

function InsertNode:is_interactive()
	return true
end

function InsertNode:child_snippets()
	local own_child_snippets = {}
	for _, child_snippet in ipairs(self.parent.snippet.child_snippets) do
		if child_snippet.parent_node == self then
			table.insert(own_child_snippets, child_snippet)
		end
	end
	return own_child_snippets
end

function InsertNode:subtree_set_pos_rgrav(pos, direction, rgrav)
	self.mark:set_rgrav(-direction, rgrav)

	local own_child_snippets = self:child_snippets()

	local child_from_indx
	if direction == 1 then
		child_from_indx = 1
	else
		child_from_indx = #own_child_snippets
	end

	node_util.nodelist_adjust_rgravs(
		own_child_snippets,
		child_from_indx,
		pos,
		direction,
		rgrav,
		-- don't assume that the child-snippets are all adjacent.
		false
	)
end

function InsertNode:subtree_set_rgrav(rgrav)
	self.mark:set_rgravs(rgrav, rgrav)

	local own_child_snippets = self:child_snippets()

	for _, child_snippet in ipairs(own_child_snippets) do
		child_snippet:subtree_set_rgrav(rgrav)
	end
end

return {
	I = I,
}
