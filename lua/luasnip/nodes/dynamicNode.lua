local DynamicNode = require("luasnip.nodes.node").Node:new()
local util = require("luasnip.util.util")
local node_util = require("luasnip.nodes.util")
local Node = require("luasnip.nodes.node").Node
local types = require("luasnip.util.types")
local events = require("luasnip.util.events")
local FunctionNode = require("luasnip.nodes.functionNode").FunctionNode
local SnippetNode = require("luasnip.nodes.snippet").SN
local extend_decorator = require("luasnip.util.extend_decorator")

local function D(pos, fn, args, opts)
	opts = opts or {}

	return DynamicNode:new({
		pos = pos,
		fn = fn,
		args = node_util.wrap_args(args),
		type = types.dynamicNode,
		mark = nil,
		user_args = opts.user_args or {},
		dependents = {},
		active = false,
	}, opts)
end
extend_decorator.register(D, { arg_indx = 4 })

function DynamicNode:input_enter(_, dry_run)
	if dry_run then
		dry_run.active[self] = true
		return
	end

	self.visited = true
	self.active = true
	self.mark:update_opts(self.ext_opts.active)

	self:event(events.enter)
end

function DynamicNode:input_leave(_, dry_run)
	if dry_run then
		dry_run.active[self] = false
		return
	end
	self:event(events.leave)

	self:update_dependents()
	self.active = false
	self.mark:update_opts(self:get_passive_ext_opts())
end

function DynamicNode:get_static_text()
	if self.static_snip then
		return self.static_snip:get_static_text()
	else
		self:update_static()
		if self.static_snip then
			return self.static_snip:get_static_text()
		else
			return { "" }
		end
	end
end

function DynamicNode:get_docstring()
	if not self.docstring then
		if self.static_snip then
			self.docstring = self.static_snip:get_docstring()
		else
			self.docstring = { "" }
		end
	end
	return self.docstring
end

-- DynamicNode's don't have static text, only set as visible.
function DynamicNode:put_initial(_)
	self.visible = true
end

function DynamicNode:indent(_) end

function DynamicNode:expand_tabs(_) end

function DynamicNode:jump_into(dir, no_move, dry_run)
	-- init dry_run-state for this node.
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

		if self.snip then
			return self.snip:jump_into(dir, no_move, dry_run)
		else
			-- this will immediately enter and leave, but IMO that's expected
			-- behaviour.
			self:input_leave(no_move, dry_run)
			if dir == 1 then
				return self.next:jump_into(dir, no_move, dry_run)
			else
				return self.prev:jump_into(dir, no_move, dry_run)
			end
		end
	end
end

function DynamicNode:update()
	local args = self:get_args()
	if vim.deep_equal(self.last_args, args) then
		-- no update, the args still match.
		return
	end

	if not self.parent.snippet:extmarks_valid() then
		error("Refusing to update inside a snippet with invalid extmarks")
	end

	local tmp
	if self.snip then
		if not args then
			-- a snippet exists, don't delete it.
			return
		end

		-- build new snippet before exiting, markers may be needed for construncting.
		tmp = self.fn(
			args,
			self.parent,
			self.snip.old_state,
			unpack(self.user_args)
		)
		self.snip:exit()
		self.snip = nil

		-- focuses node.
		self:set_text({ "" })
	else
		self:focus()
		if not args then
			-- no snippet exists, set an empty one.
			tmp = SnippetNode(nil, {})
		else
			-- also enter node here.
			tmp = self.fn(args, self.parent, nil, unpack(self.user_args))
		end
	end
	self.last_args = args

	-- act as if snip is directly inside parent.
	tmp.parent = self.parent
	tmp.indx = self.indx

	tmp.next = self
	tmp.prev = self

	tmp.snippet = self.parent.snippet

	tmp:resolve_child_ext_opts()
	tmp:resolve_node_ext_opts()
	tmp:subsnip_init()

	tmp.mark =
		self.mark:copy_pos_gravs(vim.deepcopy(tmp:get_passive_ext_opts()))
	tmp.dynamicNode = self
	tmp.update_dependents = function(node)
		node:_update_dependents()
		node.dynamicNode:update_dependents()
	end

	tmp:init_positions(self.snip_absolute_position)
	tmp:init_insert_positions(self.snip_absolute_insert_position)

	tmp:make_args_absolute()

	tmp:set_dependents()
	tmp:set_argnodes(self.parent.snippet.dependents_dict)

	if vim.bo.expandtab then
		tmp:expand_tabs(util.tab_width(), #self.parent.indentstr)
	end
	tmp:indent(self.parent.indentstr)

	-- sets own extmarks false,true
	self:focus()
	local from, to = self.mark:pos_begin_end_raw()
	-- inserts nodes with extmarks false,false
	tmp:put_initial(from)
	-- adjust gravity in left side of snippet, such that it matches the current
	-- gravity of self.
	tmp:subtree_set_pos_rgrav(to, -1, true)

	self.snip = tmp

	-- Update, tbh no idea how that could come in handy, but should be done.
	-- Both are needed, because
	-- - a node could only depend on nodes outside of tmp
	-- - a node outside of tmp could depend on one inside of tmp
	tmp:update()
	tmp:update_all_dependents()

	self:update_dependents()
end

local update_errorstring = [[
Error while evaluating dynamicNode@%d for snippet '%s':
%s
 
:h luasnip-docstring for more info]]
function DynamicNode:update_static()
	local args = self:get_static_args()
	if vim.deep_equal(self.last_static_args, args) then
		-- no update, the args still match.
		return
	end

	local tmp, ok
	if self.static_snip then
		if not args then
			-- a snippet exists, don't delete it.
			return
		end

		-- build new snippet before exiting, markers may be needed for construncting.
		ok, tmp = pcall(
			self.fn,
			args,
			self.parent,
			self.snip.old_state,
			unpack(self.user_args)
		)
	else
		if not args then
			-- no snippet exists, set an empty one.
			tmp = SnippetNode(nil, {})
		else
			-- also enter node here.
			ok, tmp =
				pcall(self.fn, args, self.parent, nil, unpack(self.user_args))
		end
	end
	if not ok then
		print(
			update_errorstring:format(self.indx, self.parent.snippet.name, tmp)
		)
		-- set empty snippet on failure
		tmp = SnippetNode(nil, {})
	end
	self.last_static_args = args

	-- act as if snip is directly inside parent.
	tmp.parent = self.parent
	tmp.indx = self.indx
	tmp.pos = rawget(self, "pos")

	tmp.next = self
	tmp.prev = self

	-- doesn't matter here, but they'll have to be set.
	tmp.ext_opts = self.parent.ext_opts
	tmp.snippet = self.parent.snippet

	tmp.dynamicNode = self
	tmp.update_dependents_static = function(node)
		node:_update_dependents_static()
		node.dynamicNode:update_dependents_static()
	end

	tmp:resolve_child_ext_opts()
	tmp:resolve_node_ext_opts()
	tmp:subsnip_init()

	tmp:init_positions(self.snip_absolute_position)
	tmp:init_insert_positions(self.snip_absolute_insert_position)

	tmp:make_args_absolute()

	tmp:set_dependents()
	tmp:set_argnodes(self.parent.snippet.dependents_dict)

	-- do not expand tabs!! This is only necessary if the snippet is inserted
	-- in a buffer, some information is lost if tabs (indent) is replaced with
	-- whitespace.
	-- This might make a difference when another f/dynamicNode depends on this
	-- one, and the function expects expanded tabs... imo the function should
	-- be adjusted to accept any whitespace.
	tmp:indent(self.parent.indentstr)

	tmp:static_init()

	tmp:update_static()
	-- updates dependents in tmp.
	tmp:update_all_dependents_static()

	self.static_snip = tmp
	-- updates own dependents.
	self:update_dependents_static()
end

function DynamicNode:exit()
	self.visible = false
	self.mark:clear()
	-- check if snip actually exists, may not be the case if
	-- the surrounding snippet was deleted just before.
	if self.snip then
		self.snip:exit()
	end
	self.stored_snip = self.snip
	self.snip = nil
	self.active = false
end

function DynamicNode:set_ext_opts(name)
	Node.set_ext_opts(self, name)

	-- might not have been generated (missing nodes).
	if self.snip then
		self.snip:set_ext_opts(name)
	end
end

function DynamicNode:store()
	if self.snip then
		self.snip:store()
	end
end

function DynamicNode:update_restore()
	-- only restore snippet if arg-values still match.
	if self.stored_snip and vim.deep_equal(self:get_args(), self.last_args) then
		local tmp = self.stored_snip

		tmp.mark =
			self.mark:copy_pos_gravs(vim.deepcopy(tmp:get_passive_ext_opts()))

		-- position might (will probably!!) still have changed, so update it
		-- here too (as opposed to only in update).
		tmp:init_positions(self.snip_absolute_position)
		tmp:init_insert_positions(self.snip_absolute_insert_position)

		tmp:make_args_absolute()

		tmp:set_dependents()
		tmp:set_argnodes(self.parent.snippet.dependents_dict)

		-- sets own extmarks false,true
		self:focus()
		-- inserts nodes with extmarks false,false
		local from, to = self.mark:pos_begin_end_raw()
		tmp:put_initial(from)
		-- adjust gravity in left side of snippet, such that it matches the current
		-- gravity of self.
		tmp:subtree_set_pos_rgrav(to, -1, true)

		-- set snip before update_restore, since update_restore involves
		-- calling `focus`, and that needs `snip` to be set.
		-- If it is not set, tmp is not reachable via get_nodes_between.
		-- (TODO: This is pretty bad, have to rethink design sometime).
		self.snip = tmp

		tmp:update_restore()
	else
		self:update()
	end
end

function DynamicNode:find_node(predicate)
	if self.snip then
		if predicate(self.snip) then
			return self.snip
		else
			return self.snip:find_node(predicate)
		end
	end
	return nil
end

function DynamicNode:insert_to_node_absolute(position)
	if #position == 0 then
		return self.absolute_position
	end
	return self.snip and self.snip:insert_to_node_absolute(position)
end

function DynamicNode:init_insert_positions(position_so_far)
	Node.init_insert_positions(self, position_so_far)
	self.snip_absolute_insert_position =
		vim.deepcopy(self.absolute_insert_position)
	-- nodes of current snippet should have a 0 before.
	self.snip_absolute_insert_position[#self.snip_absolute_insert_position + 1] =
		0
end

function DynamicNode:init_positions(position_so_far)
	Node.init_positions(self, position_so_far)
	self.snip_absolute_position = vim.deepcopy(self.absolute_position)
	-- Reach current snippet as snip_absolute_position..0.
	self.snip_absolute_position[#self.snip_absolute_position + 1] = 0
end

DynamicNode.make_args_absolute = FunctionNode.make_args_absolute
DynamicNode.set_dependents = FunctionNode.set_dependents

function DynamicNode:resolve_position(position)
	-- position must be 0, there are no other options.
	return self.snip
end

function DynamicNode:subtree_set_pos_rgrav(pos, direction, rgrav)
	self.mark:set_rgrav(-direction, rgrav)
	if self.snip then
		self.snip:subtree_set_pos_rgrav(pos, direction, rgrav)
	end
end

function DynamicNode:subtree_set_rgrav(rgrav)
	self.mark:set_rgravs(rgrav, rgrav)
	if self.snip then
		self.snip:subtree_set_rgrav(rgrav)
	end
end

function DynamicNode:extmarks_valid()
	if self.snip then
		return node_util.generic_extmarks_valid(self, self.snip)
	end
	return true
end

return {
	D = D,
}
