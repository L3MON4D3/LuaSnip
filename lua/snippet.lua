local node_mod = require'node'
local util = require'util'

local Snippet = node_mod.Node:new()

function S(trigger, nodes)
	return Snippet:new{trigger = trigger, nodes = nodes, insert_nodes = {}, current_insert = 0}
end

local function mark_pos_equal(m1, m2)
	local p1 = vim.api.nvim_buf_get_extmark_by_id(0, Ns_id, m1, {})
	local p2 = vim.api.nvim_buf_get_extmark_by_id(0, Ns_id, m2, {})
	return p1[1] == p2[1] and p1[2] == p2[2]
end

-- todo: impl exit_node
function Snippet:enter_node(node_id)
	local node = self.nodes[node_id]
	for i=1, #self.nodes, 1 do
		local other = self.nodes[i]
		if other.type > 0 then
			if mark_pos_equal(other.to, node.from) then
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
		if self.nodes[i].type > 0 then
			if mark_pos_equal(node.to, other.from) then
				other:set_from_rgrav(true)
			else
				other:set_from_rgrav(false)
			end
		end
	end
end

function Snippet:set_text(node, text)
	local node_from = vim.api.nvim_buf_get_extmark_by_id(0, Ns_id, node.from, {})
	local node_to = vim.api.nvim_buf_get_extmark_by_id(0, Ns_id, node.to, {})

	self:enter_node(node.indx)
	vim.api.nvim_buf_set_text(0, node_from[1], node_from[2], node_to[1], node_to[2], text)
end

function Snippet:exit()
	for _, node in ipairs(self.nodes) do
		vim.api.nvim_buf_del_extmark(0, Ns_id, node.from)
		vim.api.nvim_buf_del_extmark(0, Ns_id, node.to)
	end
end

function Snippet:make_args(arglist)
	local args = {}
	for i, iNs_id in ipairs(arglist) do
		args[i] = self.insert_nodes[iNs_id]:get_text()
	end
	return args
end

function Snippet:update_fn_text(node)
	self:set_text(node, node.fn(self:make_args(node.args)))
end

function Snippet:dump()
	for i, node in ipairs(self.nodes) do
		print(i)
		local c = vim.api.nvim_buf_get_extmark_by_id(0, Ns_id, node.from, {details = false})
		print(c[1], c[2])
		c = vim.api.nvim_buf_get_extmark_by_id(0, Ns_id, node.to, {details = false})
		print(c[1], c[2])
	end
end

function Snippet:expand()
	-- Snippet is node, needs from and to.
	local cur = util.get_cursor_0ind()
	self.from = vim.api.nvim_buf_set_extmark(0, Ns_id, cur[1], cur[2], {right_gravity = false})
	-- i needed for functions.
	for i, node in ipairs(self.nodes) do
		-- save cursor position for later.
		cur = util.get_cursor_0ind()

		-- Gravities are set 'pointing inwards' for static text, any text inserted on the border to a insert belongs
		-- to the insert.

		if node:has_static_text() then
			-- leaves cursor behind last char of inserted text.
			vim.api.nvim_put(node.static_text, "c", false, true);

			-- place extmark directly on previously saved position (first char
			-- of inserted text) after putting text.
			node.from = vim.api.nvim_buf_set_extmark(0, Ns_id, cur[1], cur[2], {})
		else
			-- zero-length; important that text put after doesn't move marker.
			node.from = vim.api.nvim_buf_set_extmark(0, Ns_id, cur[1], cur[2], {right_gravity = false})
		end

		cur = util.get_cursor_0ind()
		-- place extmark directly behind last char of put text.
		node.to = vim.api.nvim_buf_set_extmark(0, Ns_id, cur[1], cur[2], {right_gravity = false})

		if node.type == 1 then
			self.insert_nodes[node.pos] = node
			-- do here as long as snippets need to be defined manually
			node.dependents = {}
		end
		-- do here as long as snippets need to be defined manually
		node.indx = i
	end

	cur = util.get_cursor_0ind()
	self.to = vim.api.nvim_buf_set_extmark(0, Ns_id, cur[1], cur[2], {right_gravity = false})

	for _, node in ipairs(self.nodes) do
		if node.type == 2 then
			self:update_fn_text(node)
			-- append node to dependents-table of args.
			for _, arg in ipairs(node.args) do
				self.insert_nodes[arg].dependents[#self.insert_nodes[arg].dependents+1] = node
			end
		end
	end

	-- Jump to first insert.
	self:jump(1);
end

-- jump(-1) on first insert would jump to end of snippet (0-insert).
-- Return whether jump exited snippet.
function Snippet:jump(direction)
	-- update text in dependents on leaving node.
	for _, node in ipairs(self.insert_nodes[self.current_insert].dependents) do
		self:update_fn_text(node)
	end
	local tmp = self.current_insert + direction
	-- Would jump to invalid node?
	if self.insert_nodes[tmp] == nil then
		self.current_insert = 0
	else
		self.current_insert = tmp
	end

	self:enter_node(self.insert_nodes[self.current_insert].indx)

	util.move_to_mark(self.insert_nodes[self.current_insert].from)
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
		if node.static_text then
			for i = 2, #node.static_text do
				node.static_text[i] = prefix .. node.static_text[i]
			end
		end
	end
end

return {
	Snippet = Snippet,
	S = S
}
