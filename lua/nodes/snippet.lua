local node_mod = require'nodes.node'
local iNode = require'nodes.insertNode'
local util = require'util.util'

Luasnip_ns_id = vim.api.nvim_create_namespace("Luasnip")

local Snippet = node_mod.Node:new()

function Snippet:init_nodes()
	local insert_nodes = {}
	for i, node in ipairs(self.nodes) do
		node.parent = self
		node.indx = i
		if node.type == 1 or node.type == 4 or node.type == 5 then
			insert_nodes[node.pos] = node
		end
		if node.type == 3 then
			insert_nodes[node.pos] = node
			node.env = self.env
		end
	end

	if #insert_nodes ~= 0 then
		-- save so it can be restored later.
		local tmp = self.next

		local last_node = self
		for _, node in ipairs(insert_nodes) do
			node.prev = last_node
			last_node.next = node
			last_node = node
		end
		self.next = tmp
		insert_nodes[#insert_nodes].next = self

		self.inner_first = insert_nodes[1]
		self.inner_last = insert_nodes[#insert_nodes]
	else
		self.inner_first = self
		self.inner_last = self
	end

	self.insert_nodes = insert_nodes
end

local function S(trigger, nodes, condition, ...)
	if not condition then
		condition = function() return true end
	end
	local snip = Snippet:new{
		trigger = trigger,
		nodes = nodes,
		insert_nodes = {},
		current_insert = 0,
		condition = condition,
		user_args = {...},
		markers = {},
		dependents = {},
		active = false,
		env = {}
	}
	snip:init_nodes()
	return snip
end

local function SN(pos, nodes, condition, ...)
	if not condition then
		condition = function() return true end
	end
	local snip = Snippet:new{
		pos = pos,
		nodes = nodes,
		insert_nodes = {},
		current_insert = 0,
		condition = condition,
		user_args = {...},
		markers = {},
		dependents = {},
		active = false,
		type = 3
	}
	snip:init_nodes()
	return snip
end

local function pop_env(env)
	local cur = util.get_cursor_0ind()
	env.TM_CURRENT_LINE = vim.api.nvim_buf_get_lines(0, cur[1], cur[1]+1, false)[1]
	env.TM_CURRENT_WORD = util.word_under_cursor(cur, env.TM_CURRENT_LINE)
	env.TM_LINE_INDEX = cur[1]
	env.TM_LINE_NUMBER = cur[1]+1
	env.TM_FILENAME = vim.fn.expand("%:t")
	env.TM_FILENAME_BASE = vim.fn.expand("%:t:s?\\.[^\\.]\\+$??")
	env.TM_DIRECTORY = vim.fn.expand("%:p:h")
	env.TM_FILEPATH = vim.fn.expand("%:p")
end

function Snippet:trigger_expand(current_node)
	self:indent(util.get_current_line_to_cursor())

	pop_env(self.env)

	-- remove snippet-trigger, Cursor at start of future snippet text.
	util.remove_n_before_cur(#self.trigger)

	local start_node = iNode.I(0)
	local cur = util.get_cursor_0ind()
	-- Marks should stay at the beginning of the snippet.
	start_node.markers[1] = vim.api.nvim_buf_set_extmark(0, Luasnip_ns_id, cur[1], cur[2], {right_gravity = false})
	start_node.markers[2] = vim.api.nvim_buf_set_extmark(0, Luasnip_ns_id, cur[1], cur[2], {right_gravity = false})

	self:put_initial()

	-- needs no next.
	start_node.prev = current_node

	self.next = self.insert_nodes[0]
	self.prev = start_node

	-- Needs no prev.
	self.insert_nodes[0].next = current_node

	self:jump_into(1)
end

-- todo: impl exit_node
function Snippet:enter_node(node_id)
	local node = self.nodes[node_id]
	for i=1, #self.nodes, 1 do
		local other = self.nodes[i]
		if other.type ~= 0 then
			if util.mark_pos_equal(other.markers[2], node.markers[1]) then
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
			if util.mark_pos_equal(node.markers[2], other.markers[1]) then
				other:set_from_rgrav(true)
			else
				other:set_from_rgrav(false)
			end
			-- can be the case after expand; there all nodes without static text
			-- have left gravity on all marks.
			if util.mark_pos_equal(node.markers[2], other.markers[2]) then
				other:set_to_rgrav(true)
			end
		end
	end
end

-- https://gist.github.com/tylerneylon/81333721109155b2d244
local function copy3(obj, seen)
	-- Handle non-tables and previously-seen tables.
	if type(obj) ~= 'table' then return obj end
	if seen and seen[obj] then return seen[obj] end

	-- New table; mark it as seen an copy recursively.
	local s = seen or {}
	local res = {}
	s[obj] = res
	for k, v in next, obj do res[copy3(k, s)] = copy3(v, s) end
	return setmetatable(res, getmetatable(obj))
end

function Snippet:copy()
	return copy3(self)
end

function Snippet:set_text(node, text)
	local node_from = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, node.markers[1], {})
	local node_to = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, node.markers[2], {})

	self:enter_node(node.indx)
	vim.api.nvim_buf_set_text(0, node_from[1], node_from[2], node_to[1], node_to[2], text)
end

function Snippet:del_marks()
	for _, node in ipairs(self.nodes) do
		vim.api.nvim_buf_del_extmark(0, Luasnip_ns_id, node.markers[1])
		vim.api.nvim_buf_del_extmark(0, Luasnip_ns_id, node.markers[2])
	end
end

function Snippet:dump()
	for i, node in ipairs(self.nodes) do
		print(i)
		local c = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, node.markers[1], {details = false})
		print(c[1], c[2])
		c = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, node.markers[2], {details = false})
		print(c[1], c[2])
	end
end

function Snippet:put_initial()
	local cur = util.get_cursor_0ind()
	self.markers[1] = vim.api.nvim_buf_set_extmark(0, Luasnip_ns_id, cur[1], cur[2], {right_gravity = false})
	-- i needed for functions.
	for _, node in ipairs(self.nodes) do
		-- save cursor position for later.
		local cur1 = util.get_cursor_0ind()

		-- Gravities are set 'pointing inwards' for static text, any text inserted on the border to a insert belongs
		-- to the insert.

		-- leaves cursor behind last char of inserted text.
		node:put_initial()

		local cur2 = util.get_cursor_0ind()
		-- Will always have the same markers.
		if not (cur1[1] == cur2[1] and cur1[2] == cur2[2]) then
			-- place extmark directly on previously saved position (first char
			-- of inserted text) after putting text.
			node.markers[1] = vim.api.nvim_buf_set_extmark(0, Luasnip_ns_id, cur1[1], cur1[2], {})
		-- zero-length; important that text put after doesn't move marker.
		else
			node.markers[1] = vim.api.nvim_buf_set_extmark(0, Luasnip_ns_id, cur1[1], cur1[2], {right_gravity = false})
		end

		-- place extmark directly behind last char of put text.
		node.markers[2] = vim.api.nvim_buf_set_extmark(0, Luasnip_ns_id, cur2[1], cur2[2], {right_gravity = false})
		node:set_old_text()
	end

	cur = util.get_cursor_0ind()
	self.markers[2] = vim.api.nvim_buf_set_extmark(0, Luasnip_ns_id, cur[1], cur[2], {right_gravity = true})
	self:set_old_text()

	for _, node in ipairs(self.nodes) do
		if node.type == 2 or node.type == 5 then
			if type(node.args[1]) ~= 'table' then
				-- append node to dependents-table of args.
				for i, arg in ipairs(node.args) do
					-- Function-Node contains refs. to arg-nodes.
					node.args[i] = self.insert_nodes[arg]
					self.insert_nodes[arg].dependents[#self.insert_nodes[arg].dependents+1] = node
				end
			end
			node:update()
		end
	end
end

function Snippet:indent(line)
	local prefix = string.match(line, '^%s*')
	self.indentstr = prefix
	for _, node in ipairs(self.nodes) do
		-- put prefix behind newlines.
		if node:has_static_text() then
			for i = 2, #node:get_static_text() do
				node:get_static_text()[i] = prefix .. node:get_static_text()[i]
			end
		end
	end
end

function Snippet:input_enter()
	self.active = true
end

function Snippet:input_leave()
	self:update_dependents()
	self.active = false
end

function Snippet:jump_into(dir)
	if self.active then
		self:input_leave()
		if dir == 1 then
			self.next:jump_into(dir)
		else
			self.prev:jump_into(dir)
		end
	else
		self:input_enter()
		if dir == 1 then
			if not self.inner_first then
				print(vim.inspect(self))
				print(debug.traceback())
			end
			self.inner_first:jump_into(dir)
		else
			self.inner_last:jump_into(dir)
		end
	end
end

-- Should not happen.
function Snippet:jump_from(dir)
end

function Snippet:exit()
	for _, node in ipairs(self.nodes) do
		vim.api.nvim_buf_del_extmark(0, Luasnip_ns_id, node.markers[1])
		vim.api.nvim_buf_del_extmark(0, Luasnip_ns_id, node.markers[2])
	end
end

return {
	Snippet = Snippet,
	S = S,
	SN = SN
}
