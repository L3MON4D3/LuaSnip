local DynamicNode = require("luasnip.nodes.node").Node:new()
local util = require("luasnip.util.util")
local node_util = require("luasnip.nodes.util")
local Node = require("luasnip.nodes.node").Node
local types = require("luasnip.util.types")
local events = require("luasnip.util.events")
local FunctionNode = require("luasnip.nodes.functionNode").FunctionNode
local SnippetNode = require("luasnip.nodes.snippet").SN

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

function DynamicNode:input_enter()
	self.active = true
	self.mark:update_opts(self.ext_opts.active)

	self:event(events.enter)
end

function DynamicNode:input_leave()
	self:event(events.leave)

	self:update_dependents()
	self.active = false
	self.mark:update_opts(self.ext_opts.passive)
end

function DynamicNode:get_static_text()
	if self.snip then
		return self.snip:get_static_text()
	else
		self:update_static()
		if self.snip then
			return self.snip:get_static_text()
		else
			return { "" }
		end
	end
end

function DynamicNode:get_docstring()
	if not self.docstring then
		if self.snip then
			self.docstring = self.snip:get_docstring()
		else
			self.docstring = { "" }
		end
	end
	return self.docstring
end

-- DynamicNode's don't have static text, nop these.
function DynamicNode:put_initial(_)
	self.visible = true
end

function DynamicNode:indent(_) end

function DynamicNode:expand_tabs(_) end

function DynamicNode:jump_into(dir, no_move)
	if self.active then
		self:input_leave()
		if dir == 1 then
			return self.next:jump_into(dir, no_move)
		else
			return self.prev:jump_into(dir, no_move)
		end
	else
		self:input_enter()
		if self.snip then
			return self.snip:jump_into(dir, no_move)
		else
			-- this will immediately enter and leave, but IMO that's expected
			-- behaviour.
			self:input_leave()
			if dir == 1 then
				return self.next:jump_into(dir, no_move)
			else
				return self.prev:jump_into(dir, no_move)
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

		-- enters node.
		self.parent:set_text(self, { "" })
	else
		self.parent:enter_node(self.indx)
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

	tmp.mark = self.mark:copy_pos_gravs(vim.deepcopy(tmp.ext_opts.passive))
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

	self.parent:enter_node(self.indx)
	tmp:put_initial(self.mark:pos_begin_raw())

	-- Update, tbh no idea how that could come in handy, but should be done.
	-- Both are needed, because
	-- - a node could only depend on nodes outside of tmp
	-- - a node outside of tmp could depend on one inside of tmp
	tmp:update()
	tmp:update_all_dependents()

	self.snip = tmp
	self:update_dependents()
end

local update_errorstring = [[
Error while evaluating dynamicNode@%d for snippet '%s':
%s
 
:h luasnip-docstring for more info]]
function DynamicNode:update_static()
	local args = self:get_static_args()
	if vim.deep_equal(self.last_args, args) then
		-- no update, the args still match.
		return
	end

	local tmp, ok
	if self.snip then
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
	self.last_args = args

	-- act as if snip is directly inside parent.
	tmp.parent = self.parent
	tmp.indx = self.indx
	tmp.pos = self.pos

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

	self.snip = tmp
	-- updates own dependents.
	self:update_dependents_static()
end

function DynamicNode:set_mark_rgrav(val_begin, val_end)
	Node.set_mark_rgrav(self, val_begin, val_end)
	if self.snip then
		self.snip:set_mark_rgrav(val_begin, val_end)
	end
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
	self.mark:update_opts(self.ext_opts[name])
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
		-- prevent entering the uninitialized snip in enter_node in a few lines.
		local tmp = self.stored_snip

		tmp.mark = self.mark:copy_pos_gravs(vim.deepcopy(tmp.ext_opts.passive))

		-- position might (will probably!!) still have changed, so update it
		-- here too (as opposed to only in update).
		tmp:init_positions(self.snip_absolute_position)
		tmp:init_insert_positions(self.snip_absolute_insert_position)

		tmp:make_args_absolute()

		tmp:set_dependents()
		tmp:set_argnodes(self.parent.snippet.dependents_dict)

		self.parent:enter_node(self.indx)
		tmp:put_initial(self.mark:pos_begin_raw())
		tmp:update_restore()

		self.snip = tmp
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

return {
	D = D,
}
