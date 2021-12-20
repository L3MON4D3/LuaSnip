local session = require("luasnip.session")
local util = require("luasnip.util.util")
local node_util = require("luasnip.nodes.util")
local events = require("luasnip.util.events")

local Node = {}

function Node:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	o.visible = false
	o.old_text = {}
	return o
end

function Node:get_static_text()
	return self.static_text
end

function Node:get_docstring()
	return self.static_text
end

function Node:put_initial(pos)
	util.put(self:get_static_text(), pos)
	self.visible = true
end

function Node:input_enter(_)
	self.mark:update_opts(self.parent.ext_opts[self.type].active)

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
	local ok, text = pcall(function()
		local from_pos, to_pos = self.mark:pos_begin_end_raw()

		-- end-exclusive indexing.
		local lines = vim.api.nvim_buf_get_lines(
			0,
			from_pos[1],
			to_pos[1] + 1,
			false
		)

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

function Node:input_leave()
	self:event(events.leave)

	self.mark:update_opts(self.parent.ext_opts[self.type].passive)
end

function Node:_update_dependents()
	if self.visible and not util.multiline_equal(self.old_text, self:get_text()) then

		self.absolute_insert_position[#self.absolute_insert_position+1] = "dependents"
		local dependent_nodes = self.parent.snippet.dependents_dict:find_all(self.absolute_insert_position, "dependent")
		self.absolute_insert_position[#self.absolute_insert_position] = nil

		if not dependent_nodes then
			goto skip
		end
		for _, node in ipairs(dependent_nodes) do
			if node.visible then
				node:update()
			end
		end


		::skip::
		-- prevent future updates without changed text.
		-- if skipped, the node is missing an argnode, it will be updated from that node as soon as it becomes
		-- available.
		self.old_text = self:get_text()
	end
end

-- _update_dependents is the function to update the nodes' dependents,
-- update_dependents is what will actually be called.
-- This allows overriding update_dependents in a parent-node (eg. snippetNode)
-- while still having access to the original function (for subsequent overrides).
Node.update_dependents = Node._update_dependents
Node.update_all_dependents = Node._update_dependents

function Node:update() end

function Node:expand_tabs(tabwidth)
	util.expand_tabs(self.static_text, tabwidth)
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
	vim.cmd("doautocmd User Luasnip" .. events.to_string(self.type, event))
end

local function get_args(node, get_text_func_name)
	local args = {}

	-- Insp(node.parent.snippet.dependents_dict)
	for _, arg in ipairs(node.args_absolute) do
		-- Insp(arg)
		local arg_node = node.parent.snippet.dependents_dict:get(arg).node
		if not arg_node or not arg_node.visible then
			return nil
		end
		args[#args+1] = arg_node[get_text_func_name](arg_node)
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
	self.mark:update_opts(self.parent.ext_opts[self.type][name])
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
		local value = dict:get(self.absolute_insert_position)

		if value and value.dependents then
			value.node = self
		end
	end
end

function Node:make_args_absolute() end

function Node:resolve_position(position)
	error(string.format("invalid resolve_position(%d) on node at %s",
		position, vim.inspect(self.absolute_position) ))
end

return {
	Node = Node,
}
