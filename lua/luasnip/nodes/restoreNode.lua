-- restoreNode is implemented similarly to dynamicNode, only that it gets the snippetNode not from some function, but from self.snip.stored[key].

local Node = require("luasnip.nodes.node").Node
local wrap_nodes_in_snippetNode =
	require("luasnip.nodes.snippet").wrap_nodes_in_snippetNode
local RestoreNode = Node:new()
local types = require("luasnip.util.types")
local events = require("luasnip.util.events")
local util = require("luasnip.util.util")
local node_util = require("luasnip.nodes.util")
local mark = require("luasnip.util.mark").mark
local extend_decorator = require("luasnip.util.extend_decorator")

local function R(pos, key, nodes, opts)
	-- don't create nested snippetNodes, unnecessary.
	nodes = nodes and wrap_nodes_in_snippetNode(nodes)

	return RestoreNode:new({
		pos = pos,
		key = key,
		mark = nil,
		snip = nodes,
		type = types.restoreNode,
		dependents = {},
		-- TODO: find out why it's necessary only for this node.
		active = false,
	}, opts)
end
extend_decorator.register(R, { arg_indx = 4 })

function RestoreNode:exit()
	if not self.visible then
		-- already exited.
		return
	end

	self.visible = false
	self.mark:clear()
	-- snip should exist if exit is called.
	self.snip:store()
	-- will be copied on restore, no need to copy here too.
	self.parent.snippet.stored[self.key] = self.snip
	self.snip:exit()
	self.snip = nil
	self.active = false
end

function RestoreNode:input_enter(_, dry_run)
	if dry_run then
		dry_run.active[self] = true
		return
	end

	self.active = true
	self.visited = true
	self.mark:update_opts(self.ext_opts.active)

	self:event(events.enter)
end

function RestoreNode:input_leave(_, dry_run)
	if dry_run then
		dry_run.active[self] = false
		return
	end

	self:event(events.leave)

	self:update_dependents()
	self.active = false

	self.mark:update_opts(self:get_passive_ext_opts())
end

-- set snippetNode for this key here.
function RestoreNode:subsnip_init()
	-- don't overwrite potentially stored snippetNode.
	-- due to metatable, there will always be a node set, but only those set
	-- by it (should) have the is_default set to true.
	if self.parent.snippet.stored[self.key].is_default and self.snip then
		self.parent.snippet.stored[self.key] = self.snip
	end
end

-- don't need these, will be done in put_initial and get_static/docstring.
function RestoreNode:indent(_) end

function RestoreNode:expand_tabs(_) end

-- will be called when before expansion but after snip.parent was initialized.
-- Get the actual snippetNode here.
function RestoreNode:put_initial(pos)
	local tmp = self.parent.snippet.stored[self.key]

	-- act as if snip is directly inside parent.
	tmp.parent = self.parent
	tmp.indx = self.indx

	tmp.next = self
	tmp.prev = self

	tmp.snippet = self.parent.snippet

	tmp.restore_node = self
	tmp.update_dependents = function(node)
		node:_update_dependents()
		-- self is restoreNode.
		node.restore_node:update_dependents()
	end

	tmp:resolve_child_ext_opts()
	tmp:resolve_node_ext_opts()
	tmp:subsnip_init()

	tmp:init_positions(self.snip_absolute_position)
	tmp:init_insert_positions(self.snip_absolute_insert_position)

	tmp:make_args_absolute()

	tmp:set_dependents()
	tmp:set_argnodes(self.parent.snippet.dependents_dict)

	if vim.bo.expandtab then
		tmp:expand_tabs(util.tab_width(), self.parent.indentstring)
	end

	-- correctly set extmark for node.
	-- does not modify ext_opts[node.type].
	local mark_opts = vim.tbl_extend("keep", {
		right_gravity = false,
		end_right_gravity = false,
	}, tmp:get_passive_ext_opts())

	local old_pos = vim.deepcopy(pos)
	tmp:put_initial(pos)
	tmp.mark = mark(old_pos, pos, mark_opts)

	-- no need to call update here, will be done by function calling this
	-- function.

	self.snip = tmp
	self.visible = true
end

-- the same as DynamicNode.
function RestoreNode:jump_into(dir, no_move, dry_run)
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

		return self.snip:jump_into(dir, no_move, dry_run)
	end
end

function RestoreNode:set_ext_opts(name)
	Node.set_ext_opts(self, name)

	self.snip:set_ext_opts(name)
end

function RestoreNode:update()
	self.snip:update()
end

function RestoreNode:update_static()
	-- *_static-methods can use the stored snippet, since they don't require
	-- the snip to actually be inside the restoreNode.
	self.parent.snippet.stored[self.key]:update_static()
end

local function snip_init(self, snip)
	snip.parent = self.parent

	snip.snippet = self.parent.snippet
	-- pos should be nil if the restoreNode is inside a choiceNode.
	snip.pos = rawget(self, "pos")

	snip:resolve_child_ext_opts()
	snip:resolve_node_ext_opts()
	snip:subsnip_init()

	snip:init_positions(self.snip_absolute_position)
	snip:init_insert_positions(self.snip_absolute_insert_position)

	snip:make_args_absolute()

	snip:set_dependents()
	snip:set_argnodes(self.parent.snippet.dependents_dict)

	snip:static_init()
end

function RestoreNode:static_init()
	Node.static_init(self)
	self.snip = self.parent.snippet.stored[self.key]
	snip_init(self, self.snip)
end

function RestoreNode:get_static_text()
	-- cache static_text, no need to recalculate function.
	if not self.static_text then
		self.static_text =
			self.parent.snippet.stored[self.key]:get_static_text()
	end
	return self.static_text
end

function RestoreNode:get_docstring()
	if not self.docstring then
		self.docstring = self.parent.snippet.stored[self.key]:get_docstring()
	end
	return self.docstring
end

function RestoreNode:store() end

-- will be restored through other means.
function RestoreNode:update_restore()
	self.snip:update_restore()
end

function RestoreNode:find_node(predicate)
	if self.snip then
		if predicate(self.snip) then
			return self.snip
		else
			return self.snip:find_node(predicate)
		end
	end
	return nil
end

function RestoreNode:insert_to_node_absolute(position)
	if #position == 0 then
		return self.absolute_position
	end
	-- nil if not yet available.
	return self.snip and self.snip:insert_to_node_absolute(position)
end

function RestoreNode:update_all_dependents()
	self:_update_dependents()
	self.snip:update_all_dependents()
end

function RestoreNode:update_all_dependents_static()
	self:_update_dependents_static()
	self.parent.snippet.stored[self.key]:_update_dependents_static()
end

function RestoreNode:init_insert_positions(position_so_far)
	Node.init_insert_positions(self, position_so_far)
	self.snip_absolute_insert_position =
		vim.deepcopy(self.absolute_insert_position)
	-- nodes of current snippet should have a 0 before.
	self.snip_absolute_insert_position[#self.snip_absolute_insert_position + 1] =
		0
end

function RestoreNode:init_positions(position_so_far)
	Node.init_positions(self, position_so_far)
	self.snip_absolute_position = vim.deepcopy(self.absolute_position)
	-- Reach current snippet as snip_absolute_position..0.
	self.snip_absolute_position[#self.snip_absolute_position + 1] = 0
end

function RestoreNode:resolve_position(position)
	-- position must be 0, there are no other options.
	return self.snip
end

function RestoreNode:is_interactive()
	-- shouldn't be called, but revisit this once is_interactive is used in
	-- places other than lsp-snippets.
	return true
end

function RestoreNode:subtree_set_pos_rgrav(pos, direction, rgrav)
	self.mark:set_rgrav(-direction, rgrav)
	if self.snip then
		self.snip:subtree_set_pos_rgrav(pos, direction, rgrav)
	end
end

function RestoreNode:subtree_set_rgrav(rgrav)
	self.mark:set_rgravs(rgrav, rgrav)
	if self.snip then
		self.snip:subtree_set_rgrav(rgrav)
	end
end

function RestoreNode:extmarks_valid()
	return node_util.generic_extmarks_valid(self, self.snip)
end

return {
	R = R,
}
