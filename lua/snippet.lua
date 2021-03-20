local node_mod = require'node'
local util = require'util'

Luasnip_active_snippet = nil
Luasnip_ns_id = vim.api.nvim_create_namespace("Luasnip")
Luasnip_active_choice = nil

local Snippet = node_mod.Node:new()

function S(trigger, nodes, condition, ...)
	if not condition then
		condition = function() return true end
	end
	return Snippet:new{
		trigger = trigger,
		nodes = nodes,
		insert_nodes = {},
		current_insert = 0,
		condition = condition,
		user_args = {...}
	}
end

function SN(pos, nodes, condition, ...)
	if not condition then
		condition = function() return true end
	end
	return Snippet:new{
		pos = pos,
		nodes = nodes,
		insert_nodes = {},
		current_insert = 0,
		condition = condition,
		user_args = {...},
		type = 3
	}
end

-- todo: impl exit_node
function Snippet:enter_node(node_id)
	local node = self.nodes[node_id]
	for i=1, #self.nodes, 1 do
		local other = self.nodes[i]
		if other.type ~= 0 then
			if util.mark_pos_equal(other.to, node.from) then
				other:set_to_rgrav(false)
			else
				other:set_to_rgrav(true)
			end
		end
	end
	node:set_from_rgrav(false)
	node:set_to_rgrav(true)
	for i = node_id+1, #self.nodes, 1 do
		local other = self.nodes[i]
		if self.nodes[i].type ~= 0 then
			if util.mark_pos_equal(node.to, other.from) then
				other:set_from_rgrav(true)
			else
				other:set_from_rgrav(false)
			end
			-- can be the case after expand; there all nodes without static text
			-- have left gravity on all marks.
			if util.mark_pos_equal(node.to, other.to) then
				other:set_to_rgrav(true)
			else
				other:set_to_rgrav(false)
			end
		end
	end
end

--impl. copy for all nodes.
function Snippet:copy()
	local o = vim.deepcopy(self)
	for j, n in ipairs(self.nodes) do
		if n.type == 3 then
			o.nodes[j] = n:copy()
		else
			setmetatable(o.nodes[j], getmetatable(n))
		end
	end
	setmetatable(o, getmetatable(self))
	return o
end

function Snippet:set_text(node, text)
	local node_from = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, node.from, {})
	local node_to = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, node.to, {})

	self:enter_node(node.indx)
	vim.api.nvim_buf_set_text(0, node_from[1], node_from[2], node_to[1], node_to[2], text)
end

function Snippet:del_marks()
	for _, node in ipairs(self.nodes) do
		vim.api.nvim_buf_del_extmark(0, Luasnip_ns_id, node.from)
		vim.api.nvim_buf_del_extmark(0, Luasnip_ns_id, node.to)
	end
end

function Snippet:make_args(arglist)
	local args = {}
	for i, ins_id in ipairs(arglist) do
		args[i] = self.insert_nodes[ins_id]:get_text()
	end
	return args
end

function Snippet:update_fn_text(node)
	self:set_text(node, node.fn(self:make_args(node.args), unpack(node.user_args)))
end

function Snippet:dump()
	for i, node in ipairs(self.nodes) do
		print(i)
		local c = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, node.from, {details = false})
		print(c[1], c[2])
		c = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, node.to, {details = false})
		print(c[1], c[2])
	end
end

function Snippet:put_initial()
	self:indent(vim.api.nvim_get_current_line())
	local cur = util.get_cursor_0ind()
	-- i needed for functions.
	for i, node in ipairs(self.nodes) do
		-- save cursor position for later.
		cur = util.get_cursor_0ind()

		-- Gravities are set 'pointing inwards' for static text, any text inserted on the border to a insert belongs
		-- to the insert.

		-- leaves cursor behind last char of inserted text.
		node:put_initial()

		-- Will always have the same markers.
		if node:has_static_text() then
			-- place extmark directly on previously saved position (first char
			-- of inserted text) after putting text.
			node.from = vim.api.nvim_buf_set_extmark(0, Luasnip_ns_id, cur[1], cur[2], {})
		-- zero-length; important that text put after doesn't move marker.
		else
			node.from = vim.api.nvim_buf_set_extmark(0, Luasnip_ns_id, cur[1], cur[2], {right_gravity = false})
		end

		-- place extmark directly behind last char of put text.
		cur = util.get_cursor_0ind()
		node.to = vim.api.nvim_buf_set_extmark(0, Luasnip_ns_id, cur[1], cur[2], {right_gravity = false})

		if node.type == 1 or node.type == 3 then
			self.insert_nodes[node.pos] = node
			-- do here as long as snippets need to be defined manually
			node.dependents = {}
		end
		-- do here as long as snippets need to be defined manually
		node.indx = i
	end

	cur = util.get_cursor_0ind()

	for _, node in ipairs(self.nodes) do
		if node.type == 2 then
			self:update_fn_text(node)
			-- append node to dependents-table of args.
			for _, arg in ipairs(node.args) do
				self.insert_nodes[arg].dependents[#self.insert_nodes[arg].dependents+1] = node
			end
		end
	end
end

-- jump(-1) on first insert would jump to end of snippet (0-insert).
-- Return whether jump exited snippet.
function Snippet:jump(direction)
	-- update text in dependents on leaving node.
	for _, node in ipairs(self.insert_nodes[self.current_insert].dependents) do
		self:update_fn_text(node)
	end

	self.insert_nodes[self.current_insert]:input_leave()

	local tmp = self.current_insert + direction
	-- Would jump to invalid node?
	if self.insert_nodes[tmp] == nil then
		self.current_insert = 0
	else
		self.current_insert = tmp
	end

	self:enter_node(self.insert_nodes[self.current_insert].indx)
	self.insert_nodes[self.current_insert]:input_enter()

	if self.current_insert == 0 then
		self:exit()
		return true
	end
	return false
end

function Snippet:indent(line)
	local prefix = string.match(line, '^%s*')
	for _, node in ipairs(self.nodes) do
		-- put prefix behind newlines.
		if node:has_static_text() then
			for i = 2, #node.static_text do
				node.static_text[i] = prefix .. node.static_text[i]
			end
		end
	end
end

function Snippet:input_enter()
	self.parent = Luasnip_active_snippet
	Luasnip_active_snippet = self
	self:jump(1)
end

function Snippet:input_leave()
	Luasnip_active_snippet = self.parent
end

function Snippet:exit()
	for _, node in ipairs(self.nodes) do
		vim.api.nvim_buf_del_extmark(0, Luasnip_ns_id, node.from)
		vim.api.nvim_buf_del_extmark(0, Luasnip_ns_id, node.to)
	end
end

return {
	Snippet = Snippet,
	S = S,
	SN = SN
}
