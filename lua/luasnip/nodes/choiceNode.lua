local Node = require("luasnip.nodes.node").Node
local util = require("luasnip.util.util")
local node_util = require("luasnip.nodes.util")
local types = require("luasnip.util.types")
local events = require("luasnip.util.events")
local mark = require("luasnip.util.mark").mark
local session = require("luasnip.session")
local sNode = require("luasnip.nodes.snippet").SN
local extend_decorator = require("luasnip.util.extend_decorator")
local feedkeys = require("luasnip.util.feedkeys")
local log = require("luasnip.util.log").new("choice")

---@class LuaSnip.ChoiceNode.ItemNode: LuaSnip.Node

---@class LuaSnip.ChoiceNode: LuaSnip.Node
---@field choices LuaSnip.ChoiceNode.ItemNode[]
local ChoiceNode = Node:new()

function ChoiceNode:init_nodes()
	for i, choice in ipairs(self.choices) do
		-- setup jumps
		choice.next = self
		choice.prev = self

		-- forward values for unknown keys from choiceNode.
		choice.choice = self

		choice.next_choice = self.choices[i + 1]
		choice.prev_choice = self.choices[i - 1]
	end
	self.choices[#self.choices].next_choice = self.choices[1]
	self.choices[1].prev_choice = self.choices[#self.choices]

	self.active_choice = self.choices[1]
end

---@class LuaSnip.Opts.ChoiceNode: LuaSnip.Opts.Node
---@field restore_cursor? boolean If set, the currently active node is looked up
---  in the switched-to choice, and the cursor restored to  preserve the current
---  position relative to that node. The node may be found if a `restoreNode` is
---  present in both choice.
---  Defaults to `false`, as enabling might lead to decreased performance.
---
---  It's possible to override the default by wrapping the `choiceNode`
---  constructor in another function that sets `opts.restore_cursor` to `true` and
---  then using that to construct `choiceNode`s:
---  ```lua
---  local function restore_cursor_choice(pos, choices, opts)
---      opts = opts or {}
---      opts.restore_cursor = true
---      return c(pos, choices, opts)
---  end
---  ```
---  Consider passing this override into `snip_env`.
---
---@field node_callbacks? {["change_choice"|"enter"|"leave"]: fun(node:LuaSnip.Node)}
---  Specify functions to call after changing the choice, or entering or leaving
---  the node. The callback receives the `node` the callback was called on.

--- Create a new choiceNode from a list of choices.
--- The first item in this list is the initial choice, and it can be changed
--- while any node of a choice is active. So, if all choices should be
--- reachable, every choice has to have a place for the cursor to stop at.
---
--- If the choice is a snippetNode like `sn(nil, {...nodes...})` the given
--- `nodes` have to contain an `insertNode` (e.g. `i(1)`). Using an `insertNode`
--- or `textNode` directly as a choice is also fine, the latter is special-cased
--- to have a jump-point at the beginning of its text.
---@param pos integer Jump-index of the node.
---  (See [Basics-Jump-Index](../../../DOC.md#jump-index))
---
---@param choices (LuaSnip.Node|LuaSnip.Node[])[] A list of nodes that can be
---  switched between interactively. If a list of nodes is passed as a choice,
---  it will be turned into a snippetNode.
---  Jumpable nodes that generally need a jump-index don't need one when used as
---  a choice since they inherit the choiceNode's jump-index anyway.
---
---@param opts? LuaSnip.Opts.ChoiceNode Additional optional arguments.
---@return LuaSnip.ChoiceNode
function ChoiceNode.C(pos, choices, opts)
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
	}, opts)
	c:init_nodes()
	return c
end
extend_decorator.register(ChoiceNode.C, { arg_indx = 3 })

function ChoiceNode:subsnip_init()
	for _, choice in ipairs(self.choices) do
		choice.parent = self.parent
		-- only insertNode needs this.
		if choice.type == 2 or choice.type == 1 or choice.type == 3 then
			choice.pos = self.pos
		end
	end
	node_util.subsnip_init_children(self.parent, self.choices)
end

ChoiceNode.init_positions = node_util.init_child_positions_func(
	"absolute_position",
	"choices",
	"init_positions"
)
ChoiceNode.init_insert_positions = node_util.init_child_positions_func(
	"absolute_insert_position",
	"choices",
	"init_insert_positions"
)

function ChoiceNode:make_args_absolute()
	-- relative indices are relative to the parent of the choiceNode,
	-- temporarily remove last component of position
	local last_indx = #self.absolute_insert_position
	local last = self.absolute_insert_position[last_indx]
	self.absolute_insert_position[#self.absolute_insert_position] = nil

	for _, choice in ipairs(self.choices) do
		-- relative to choiceNode!!
		choice:make_args_absolute(self.absolute_insert_position)
	end

	self.absolute_insert_position[last_indx] = last
end

function ChoiceNode:put_initial(pos)
	local old_pos = vim.deepcopy(pos)

	self.active_choice:put_initial(pos)

	local mark_opts = vim.tbl_extend("keep", {
		right_gravity = false,
		end_right_gravity = false,
	}, self.active_choice:get_passive_ext_opts())

	self.active_choice.mark = mark(old_pos, pos, mark_opts)
	self.visible = true
end

function ChoiceNode:indent(indentstr)
	for _, node in ipairs(self.choices) do
		node:indent(indentstr)
	end
end

function ChoiceNode:expand_tabs(tabwidth, indentstringlen)
	for _, node in ipairs(self.choices) do
		node:expand_tabs(tabwidth, indentstringlen)
	end
end

function ChoiceNode:input_enter(_, dry_run)
	if dry_run then
		dry_run.active[self] = true
		return
	end

	self.mark:update_opts(self.ext_opts.active)
	self:focus()

	self.prev_choice_node =
		session.active_choice_nodes[vim.api.nvim_get_current_buf()]
	session.active_choice_nodes[vim.api.nvim_get_current_buf()] = self
	self.visited = true
	self.active = true
	self.input_active = true

	self:event(events.enter)
end

function ChoiceNode:input_leave(_, dry_run)
	if dry_run then
		dry_run.active[self] = false
		return
	end

	self.input_active = false

	self:event(events.leave)

	self.mark:update_opts(self:get_passive_ext_opts())

	session.active_choice_nodes[vim.api.nvim_get_current_buf()] =
		self.prev_choice_node
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
		self.pos
	)
end

function ChoiceNode:jump_into(dir, no_move, dry_run)
	self:init_dry_run_active(dry_run)

	if self:is_active(dry_run) then
		self:input_leave(no_move, dry_run)

		if dir == 1 then
			return self.next:jump_into(dir, no_move, dry_run)
		else
			return self.prev:jump_into(dir, no_move, dry_run)
		end
	else
		self:input_enter(no_move, dry_run)

		return self.active_choice:jump_into(dir, no_move, dry_run)
	end
end

function ChoiceNode:update()
	self.active_choice:update()
end

function ChoiceNode:update_static_all()
	for _, choice in ipairs(self.choices) do
		choice:update_static()
	end
end

function ChoiceNode:update_static()
	self.active_choice:update_static()
end

function ChoiceNode:update_restore()
	self.active_choice:update_restore()
end

function ChoiceNode:setup_choice_jumps() end

function ChoiceNode:find_node(predicate, opts)
	if self.active_choice then
		if predicate(self.active_choice) then
			return self.active_choice
		else
			return self.active_choice:find_node(predicate, opts)
		end
	end
	return nil
end

-- used to uniquely identify this change-choice-action.
local change_choice_id = 0

function ChoiceNode:set_choice(choice, current_node)
	change_choice_id = change_choice_id + 1
	-- to uniquely identify this node later (storing the pointer isn't enough
	-- because this is supposed to work with restoreNodes, which are copied).
	current_node.change_choice_id = change_choice_id

	local insert_pre_cc = vim.fn.mode() == "i"
	-- is byte-indexed! Doesn't matter here, but important to be aware of.
	local cursor_node_offset =
		util.pos_offset(current_node.mark:pos_begin(), util.get_cursor_0ind())

	self.active_choice:store()

	-- tear down current choice.
	-- leave all so the choice (could be a snippet) is in the correct state for
	-- the next enter.
	node_util.refocus(current_node, self.active_choice)

	self.active_choice:exit()

	-- clear text.
	--
	-- active_choice has to be disabled (nilled?) to prevent reading from
	-- cleared mark in set_mark_rgrav (which will be called in
	-- self:set_text_raw({""}) a few lines below).
	self.active_choice = nil
	self:set_text_raw({ "" })

	self.active_choice = choice

	self.active_choice.mark = self.mark:copy_pos_gravs(
		vim.deepcopy(self.active_choice:get_passive_ext_opts())
	)

	-- re-init positions for child-restoreNodes (they will update their
	-- children in put_initial, but their own position has to be changed here).
	self:init_positions(self.absolute_position)
	self:init_insert_positions(self.absolute_insert_position)

	-- self is still focused, from `set_text`.
	self.active_choice:put_initial(self.mark:pos_begin_raw())
	-- adjust gravity in left side of inserted node, such that it matches the
	-- current gravity of self.
	local _, to = self.mark:pos_begin_end_raw()
	self.active_choice:subtree_set_pos_rgrav(to, -1, true)

	self.active_choice:update_restore()
	-- update outside dependents later, in init.lua:set_choice!

	self:event(events.change_choice)

	if self.restore_cursor then
		local target_node = self:find_node(function(test_node)
			return test_node.change_choice_id == change_choice_id
		end, {find_in_child_snippets = true})

		if target_node then
			-- the node that the cursor was in when changeChoice was called
			-- exists in the active choice! Enter it and all nodes between it
			-- and this choiceNode, then set the cursor.

			node_util.refocus(self, target_node)

			if insert_pre_cc then
				feedkeys.move_to(
					util.pos_from_offset(
						target_node.mark:pos_begin(),
						cursor_node_offset
					)
				)
			else
				node_util.select_node(target_node)
			end
			return target_node
		end
	end

	return self.active_choice:jump_into(1)
end

function ChoiceNode:change_choice(dir, current_node)
	-- stylua: ignore
	return self:set_choice(
		dir == 1 and self.active_choice.next_choice
		          or self.active_choice.prev_choice,
		current_node )
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
	self.visible = false
	if self.active_choice then
		self.active_choice:exit()
	end
	self.mark:clear()
	if self.active then
		session.active_choice_nodes[vim.api.nvim_get_current_buf()] =
			self.prev_choice_node
	end
	self.active = false
end

function ChoiceNode:set_ext_opts(name)
	Node.set_ext_opts(self, name)

	self.active_choice:set_ext_opts(name)
end

function ChoiceNode:store()
	self.active_choice:store()
end

function ChoiceNode:insert_to_node_absolute(position)
	if #position == 0 then
		return self.absolute_position
	end
	local front = util.pop_front(position)
	return self.choices[front]:insert_to_node_absolute(position)
end

function ChoiceNode:set_dependents()
	for _, node in ipairs(self.choices) do
		node:set_dependents()
	end
end

function ChoiceNode:set_argnodes(dict)
	Node.set_argnodes(self, dict)

	for _, node in ipairs(self.choices) do
		node:set_argnodes(dict)
	end
end

function ChoiceNode:resolve_position(position)
	return self.choices[position]
end

function ChoiceNode:static_init()
	Node.static_init(self)
	self.active_choice:static_init()
end

function ChoiceNode:subtree_set_pos_rgrav(pos, direction, rgrav)
	self.mark:set_rgrav(-direction, rgrav)
	if self.active_choice then
		self.active_choice:subtree_set_pos_rgrav(pos, direction, rgrav)
	end
end

function ChoiceNode:subtree_set_rgrav(rgrav)
	self.mark:set_rgravs(rgrav, rgrav)
	if self.active_choice then
		self.active_choice:subtree_set_rgrav(rgrav)
	end
end

function ChoiceNode:extmarks_valid()
	return node_util.generic_extmarks_valid(self, self.active_choice)
end

function ChoiceNode:subtree_do(opts)
	opts.pre(self)
	self.active_choice:subtree_do(opts)
	opts.post(self)
end

function ChoiceNode:subtree_leave_entered()
	if self.input_active then
		self.active_choice:subtree_leave_entered()
		self:input_leave()
	end
end

return {
	C = ChoiceNode.C,
}
