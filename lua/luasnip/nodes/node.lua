local session = require("luasnip.session")
local util = require("luasnip.util.util")
local types = require("luasnip.util.types")
local node_util = require("luasnip.nodes.util")
local ext_util = require("luasnip.util.ext_opts")
local events = require("luasnip.util.events")

local Node = {}

function Node:new(o, opts)
	o = o or {}

	-- visible is true if the node is visible on-screen, during normal
	-- expansion, static_visible is needed for eg. get_static_text, where
	-- argnodes in inactive choices will happily provide their static text,
	-- which leads to inaccurate docstrings.
	o.visible = false
	o.static_visible = false
	o.old_text = {}
	o.visited = false
	-- override existing keys, might be necessary due to double-init from
	-- snippetProxy, but shouldn't hurt.
	o = vim.tbl_extend("force", o, node_util.init_node_opts(opts or {}))

	setmetatable(o, self)
	self.__index = self

	return o
end

function Node:get_static_text()
	-- return nil if not visible.
	-- This will prevent updates if not all nodes are visible during
	-- docstring/static_text-generation. (One example that would otherwise fail
	-- is the following snippet:
	--
	-- s("trig", {
	-- 	i(1, "cccc"),
	-- 	t" ",
	-- 	c(2, {
	-- 		t"aaaa",
	-- 		i(nil, "bbbb")
	-- 	}),
	-- 	f(function(args) return args[1][1]..args[2][1] end, {ai[2][2], 1} )
	-- })
	--
	-- )
	if not self.static_visible then
		return nil
	end
	return self.static_text
end

function Node:get_docstring()
	-- visibility only matters for get_static_text because that's called for
	-- argnodes whereas get_docstring will only be called for actually
	-- visible nodes.
	return self.static_text
end

function Node:put_initial(pos)
	-- access static text directly, get_static_text() won't work due to
	-- static_visible not being set.
	util.put(self.static_text, pos)
	self.visible = true
end

function Node:input_enter(_)
	self.visited = true
	self.mark:update_opts(self.ext_opts.active)

	self:event(events.enter)
end

function Node:jump_into(_, no_move)
	self:input_enter(no_move)
	return self
end

function Node:jump_from(dir, no_move)
	self:input_leave()
	if dir == 1 then
		if self.next then
			return self.next:jump_into(dir, no_move)
		else
			return nil
		end
	else
		if self.prev then
			return self.prev:jump_into(dir, no_move)
		else
			return nil
		end
	end
end

function Node:jumpable(dir)
	if dir == 1 then
		return self.next ~= nil
	else
		return self.prev ~= nil
	end
end

function Node:set_mark_rgrav(rgrav_beg, rgrav_end)
	self.mark:update_rgravs(rgrav_beg, rgrav_end)
end

function Node:get_text()
	if not self.visible then
		return nil
	end
	local ok, text = pcall(function()
		local from_pos, to_pos = self.mark:pos_begin_end_raw()

		-- end-exclusive indexing.
		local lines =
			vim.api.nvim_buf_get_lines(0, from_pos[1], to_pos[1] + 1, false)

		if #lines == 1 then
			lines[1] = string.sub(lines[1], from_pos[2] + 1, to_pos[2])
		else
			lines[1] = string.sub(lines[1], from_pos[2] + 1, #lines[1])

			-- node-range is end-exclusive.
			lines[#lines] = string.sub(lines[#lines], 1, to_pos[2])
		end
		return lines
	end)
	-- if deleted.
	return ok and text or { "" }
end

function Node:set_old_text()
	self.old_text = self:get_text()
end

function Node:exit()
	self.visible = false
	self.mark:clear()
end

function Node:get_passive_ext_opts()
	if self.visited then
		return self.ext_opts.visited
	else
		return self.ext_opts.unvisited
	end
end

function Node:input_leave()
	self:event(events.leave)

	self.mark:update_opts(self:get_passive_ext_opts())
end

local function find_dependents(self, position_self, dict)
	local nodes = {}

	position_self[#position_self + 1] = "dependents"
	vim.list_extend(nodes, dict:find_all(position_self, "dependent") or {})
	position_self[#position_self] = nil

	vim.list_extend(
		nodes,
		dict:find_all({ self, "dependents" }, "dependent") or {}
	)

	return nodes
end

function Node:_update_dependents()
	local dependent_nodes = find_dependents(
		self,
		self.absolute_insert_position,
		self.parent.snippet.dependents_dict
	)
	if #dependent_nodes == 0 then
		return
	end
	for _, node in ipairs(dependent_nodes) do
		if node.visible then
			node:update()
		end
	end
end

-- _update_dependents is the function to update the nodes' dependents,
-- update_dependents is what will actually be called.
-- This allows overriding update_dependents in a parent-node (eg. snippetNode)
-- while still having access to the original function (for subsequent overrides).
Node.update_dependents = Node._update_dependents
-- update_all_dependents is used to update all nodes' dependents in a
-- snippet-tree. Necessary in eg. set_choice (especially since nodes may have
-- dependencies outside the tree itself, so update_all_dependents should take
-- care of those too.)
Node.update_all_dependents = Node._update_dependents

function Node:_update_dependents_static()
	local dependent_nodes = find_dependents(
		self,
		self.absolute_insert_position,
		self.parent.snippet.dependents_dict
	)
	if #dependent_nodes == 0 then
		return
	end
	for _, node in ipairs(dependent_nodes) do
		if node.static_visible then
			node:update_static()
		end
	end
end

Node.update_dependents_static = Node._update_dependents_static
Node.update_all_dependents_static = Node._update_dependents_static

function Node:update() end
function Node:update_static() end

function Node:expand_tabs(tabwidth, indentstr)
	util.expand_tabs(self.static_text, tabwidth, indentstr)
end

function Node:indent(indentstr)
	util.indent(self.static_text, indentstr)
end

function Node:subsnip_init() end

function Node:init_positions(position_so_far)
	self.absolute_position = vim.deepcopy(position_so_far)
end

function Node:init_insert_positions(position_so_far)
	self.absolute_insert_position = vim.deepcopy(position_so_far)
end

function Node:event(event)
	if self.pos then
		-- node needs position to get callback (nodes may not have position if
		-- defined in a choiceNode, ie. c(1, {
		--	i(nil, {"works!"})
		-- }))
		-- works just fine.
		local callback = self.parent.callbacks[self.pos][event]
		if callback then
			callback(self)
		end
	end

	session.event_node = self
	vim.cmd(
		"doautocmd <nomodeline> User Luasnip"
			.. events.to_string(self.type, event)
	)
end

local function get_args(node, get_text_func_name)
	local args = {}

	-- Insp(node.parent.snippet.dependents_dict)
	for _, arg in pairs(node.args_absolute) do
		-- since arg may be a node, it may not be initialized in the snippet
		-- and therefore not have an absolute_insert_position. Check for that.
		if not arg.absolute_insert_position then
			-- the node is not (yet, maybe) visible.
			return nil
		end
		local arg_table = node.parent.snippet.dependents_dict:get(
			arg.absolute_insert_position
		)
		if not arg_table then
			return nil
		end
		local arg_node = arg_table.node
		-- maybe the node is part of a dynamicNode and not yet generated.
		if not arg_node then
			return nil
		end
		local argnode_text = arg_node[get_text_func_name](arg_node)
		-- can only occur with `get_text`. If one returns nil, the argnode
		-- isn't visible or some other error occured. Either way, return nil
		-- to signify that not all argnodes are available.
		if not argnode_text then
			return nil
		end
		args[#args + 1] = arg_node[get_text_func_name](arg_node)
	end

	return args
end

function Node:get_args()
	return get_args(self, "get_text")
end
function Node:get_static_args()
	return get_args(self, "get_static_text")
end

function Node:set_ext_opts(name)
	-- differentiate, either visited or unvisited needs to be set.
	if name == "passive" then
		self.mark:update_opts(self:get_passive_ext_opts())
	else
		self.mark:update_opts(self.ext_opts[name])
	end
end

-- for insert,functionNode.
function Node:store()
	self.static_text = self:get_text()
end

function Node:update_restore() end

-- find_node only needs to check children, self is checked by the parent.
function Node:find_node()
	return nil
end

Node.ext_gravities_active = { false, true }

function Node:insert_to_node_absolute(position)
	-- this node is a leaf, just return its position
	return self.absolute_position
end

function Node:set_dependents() end

function Node:set_argnodes(dict)
	if self.absolute_insert_position then
		-- append+remove "node" from absolute_insert_position to quickly create
		-- key for dict.
		table.insert(self.absolute_insert_position, "node")
		dict:set(self.absolute_insert_position, self)
		self.absolute_insert_position[#self.absolute_insert_position] = nil
	end
end

function Node:make_args_absolute() end

function Node:resolve_position(position)
	error(
		string.format(
			"invalid resolve_position(%d) on node at %s",
			position,
			vim.inspect(self.absolute_position)
		)
	)
end

function Node:static_init()
	self.static_visible = true
end

-- resolve_*node*_ext_opts because snippet(Node)s have child_ext_opts, which
-- also have to be resolved.
-- This function generates a nodes ext_opts (those actually used in highlighting).
function Node:resolve_node_ext_opts(base_prio, parent_ext_opts)
	if self.merge_node_ext_opts then
		self.ext_opts = ext_util.extend(
			vim.deepcopy(self.node_ext_opts),
			parent_ext_opts or self.parent.effective_child_ext_opts[self.type]
		)
	else
		self.ext_opts = self.node_ext_opts
	end

	ext_util.set_abs_prio(
		self.ext_opts,
		(base_prio or self.parent.ext_opts.base_prio)
			+ session.config.ext_prio_increase
	)
end

function Node:is_interactive()
	-- safe default.
	return true
end

return {
	Node = Node,
}
