local Node = require("luasnip.nodes.node")
local InsertNode = Node.Node:new()
local ExitNode = InsertNode:new()
local util = require("luasnip.util.util")
local node_util = require("luasnip.nodes.util")
local types = require("luasnip.util.types")
local events = require("luasnip.util.events")
local extend_decorator = require("luasnip.util.extend_decorator")
local feedkeys = require("luasnip.util.feedkeys")
local snippet_string = require("luasnip.nodes.util.snippet_string")
local str_util = require("luasnip.util.str")
local log = require("luasnip.util.log").new("insertNode")
local session = require("luasnip.session")

local function I(pos, static_text, opts)
	if not snippet_string.isinstance(static_text) then
		static_text = snippet_string.new(util.to_string_table(static_text))
	end

	local node
	if pos == 0 then
		node = ExitNode:new({
			pos = pos,
			mark = nil,
			dependents = {},
			type = types.exitNode,
			-- will only be needed for 0-node, -1-node isn't set with this.
			ext_gravities_active = { false, false },
			inner_active = false,
			input_active = false,
		}, opts)
	else
		node = InsertNode:new({
			pos = pos,
			mark = nil,
			dependents = {},
			type = types.insertNode,
			inner_active = false,
			input_active = false,
		}, opts)
	end

	-- make static text owned by this insertNode.
	-- This includes copying it so that it is separate from the snippets that
	-- were potentially captured in `get_args`.
	node.static_text = static_text:copy()
	return node
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
			feedkeys.insert_at(begin_pos)
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

	self.input_active = false

	if self.pos == 0 then
		InsertNode.input_leave(self, no_move, dry_run)
	else
		self:event(events.leave)
	end
end

function ExitNode:is_interactive()
	return true
end

function InsertNode:input_enter(no_move, dry_run)
	if dry_run then
		return
	end

	self.visited = true
	self.input_active = true
	self.mark:update_opts(self.ext_opts.active)

	-- no_move only prevents moving the cursor, but the active node should
	-- still be focused.
	self:focus()

	if not no_move then
		-- SELECT snippet text only when there is text to select (more oft than not there isnt).
		local mark_begin_pos, mark_end_pos = self.mark:pos_begin_end_raw()
		if not util.pos_equal(mark_begin_pos, mark_end_pos) then
			feedkeys.select_range(mark_begin_pos, mark_end_pos)
		else
			feedkeys.insert_at(mark_begin_pos)
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

	self.input_active = false
	self:event(events.leave)

	self.mark:update_opts(self:get_passive_ext_opts())
end

function InsertNode:exit()
	for _, snip in ipairs(self:child_snippets()) do
		snip:remove_from_jumplist()
	end

	-- reset runtime-acquired values.
	self.visible = false
	self.inner_first = nil
	self.inner_last = nil
	self.inner_active = false
	self.input_active = false
	self.mark:clear()
end

function InsertNode:get_docstring()
	-- copy as to not in-place-modify static text.
	return util.string_wrap(self:get_static_text(), self.pos)
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

function InsertNode:subtree_leave_entered()
	if not self.input_active then
		-- is not directly active, and does not contain an active child.
		return
	else
		-- first leave children, if they're active, then self.
		if self.inner_active then
			local nested_snippets = self:child_snippets()
			for _, snippet in ipairs(nested_snippets) do
				snippet:subtree_leave_entered()
			end
			self:input_leave_children()
		end
		self:input_leave()
	end
end

function InsertNode:get_snippetstring()
	if not self.visible then
		return nil
	end

	-- in order to accurately capture all the nodes inside eventual snippets,
	-- call :store(), so these are up-to-date in the snippetString.
	for _, snip in ipairs(self:child_snippets()) do
		snip:store()
	end

	local self_from, self_to = self.mark:pos_begin_end_raw()
	-- only do one get_text, and establish relative offsets partition this
	-- text.
	local ok, text = pcall(
		vim.api.nvim_buf_get_text,
		0,
		self_from[1],
		self_from[2],
		self_to[1],
		self_to[2],
		{}
	)

	local snippetstring = snippet_string.new(
		nil,
		{ luasnip_changedtick = session.luasnip_changedtick }
	)

	if not ok then
		log.warn("Failure while getting text of insertNode: " .. text)
		-- return empty in case of failure.
		return snippetstring
	end

	local current = { 0, 0 }
	for _, snip in ipairs(self:child_snippets()) do
		local snip_from, snip_to = snip.mark:pos_begin_end_raw()
		local snip_from_base_rel = util.pos_offset(self_from, snip_from)
		local snip_to_base_rel = util.pos_offset(self_from, snip_to)

		snippetstring:append_text(
			str_util.multiline_substr(text, current, snip_from_base_rel)
		)
		snippetstring:append_snip(
			snip,
			str_util.multiline_substr(
				text,
				snip_from_base_rel,
				snip_to_base_rel
			)
		)
		current = snip_to_base_rel
	end
	snippetstring:append_text(
		str_util.multiline_substr(
			text,
			current,
			util.pos_offset(self_from, self_to)
		)
	)

	return snippetstring
end
function InsertNode:get_static_snippetstring()
	return self.static_text
end

function InsertNode:expand_tabs(tabwidth, indentstrlen)
	self.static_text:expand_tabs(tabwidth, indentstrlen)
end

function InsertNode:indent(indentstr)
	self.static_text:indent(indentstr)
end

-- generate and cache text of this node when used as an argnode.
function InsertNode:store()
	if
		session.luasnip_changedtick
		and self.static_text.metadata
		and self.static_text.metadata.luasnip_changedtick
			== session.luasnip_changedtick
	then
		-- stored data is up-to-date, just return the static text.
		return
	end

	-- get_snippetstring calls store for all child-snippets.
	self.static_text = self:get_snippetstring()
end

function InsertNode:argnode_text()
	-- store caches its text, which is exactly what we want here!
	self:store()
	return self.static_text
end

function InsertNode:put_initial(pos)
	self.static_text:put(pos)
	self.visible = true
	local _, child_snippet_idx = node_util.binarysearch_pos(
		self.parent.snippet.child_snippets,
		pos,
		-- we are always focused on this node when this is called (I'm pretty
		-- sure at least), so we should follow the gravity when finding this
		-- index.
		true,
		-- don't enter snippets, we want to find the position of this node.
		node_util.binarysearch_preference.outside
	)

	for snip in self.static_text:iter_snippets() do
		-- don't have to pass a current_node, we don't need it since we can
		-- certainly link the snippet into this insertNode.
		snip:insert_into_jumplist(
			nil,
			self,
			self.parent.snippet.child_snippets,
			child_snippet_idx
		)

		child_snippet_idx = child_snippet_idx + 1
	end
end

function InsertNode:get_static_text()
	return vim.split(self.static_text:str(), "\n")
end

function InsertNode:set_text(text)
	local text_indented = util.indent(text, self.parent.indentstr)

	if self:get_snippet().___static_expanded then
		self.static_text = snippet_string.new(text_indented)
		self:update_dependents_static({ own = true, parents = true })
	else
		if self.visible then
			self:set_text_raw(text_indented)
			self:update_dependents({ own = true, parents = true })
		end
	end
end

function InsertNode:find_node(predicate, opts)
	if opts and opts.find_in_child_snippets then
		for _, snip in ipairs(self:child_snippets()) do
			local node_in_child = snip:find_node(predicate, opts)
			if node_in_child then
				return node_in_child
			end
		end
	end
	return nil
end

function InsertNode:update_restore()
	for _, snip in pairs(self:child_snippets()) do
		snip:update_restore()
	end
end

function InsertNode:subtree_do(opts)
	opts.pre(self)
	if opts.do_child_snippets then
		for _, snip in ipairs(self:child_snippets()) do
			snip:subtree_do(opts)
		end
	end
	opts.post(self)
end

return {
	I = I,
}
