local active_snippet = nil
local ns_id = vim.api.nvim_create_namespace("luasnip")

local function get_active_snip() return active_snippet end

local function copy(args) return args[1] end

Node = {}

function Node:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end


TextNode = Node:new()
InsertNode = Node:new()
FunctionNode = Node:new()
Snippet = Node:new()

function t(static_text)
	return TextNode:new{static_text = static_text, type = 0}
end

function i(pos, static_text)
	return InsertNode:new{pos = pos, static_text = static_text, dependents = {}, type = 1}
end

function f(fn, args)
	return FunctionNode:new{fn = fn, args = args, type = 2}
end

function s(trigger, nodes)
	return Snippet:new{trigger = trigger, nodes = nodes, insert_nodes = {}, current_insert = 0}
end

local snippets = {
	s("fn", {
		t({"function "}),
		i(1),
		t({"("}),
		i(2, {"lel"}),
		t({")"}),
		f(copy, {2}),
		t({" {","\t"}),
		i(0),
		t({"", "}"})
	})
}

local function get_cursor_0ind()
	local c = vim.api.nvim_win_get_cursor(0)
	c[1] = c[1] - 1
	return c
end

local function set_cursor_0ind(c)
	c[1] = c[1] + 1
	vim.api.nvim_win_set_cursor(0, c)
end

-- returns snippet-object where its trigger matches the end of the line, nil if no match.
local function match_snippet(line)
	for i = 1, #snippets do
		local snip = snippets[i]
		-- if line ends with trigger
		if string.sub(line, #line - #snip.trigger + 1, #line) == snip.trigger then
			local o = vim.deepcopy(snip)
			for j, n in ipairs(snip.nodes) do
				setmetatable(o.nodes[j], getmetatable(n))
			end
			setmetatable(o, getmetatable(snip))
			return o
		end
	end
	return nil
end

function Node:has_static_text()
	return self.static_text and not (self.static_text[1] == "" and #self.static_text == 1)
end

local function move_to_mark(id)
	local new_cur_pos
	new_cur_pos = vim.api.nvim_buf_get_extmark_by_id(
		0, ns_id, id, {details = false})
	set_cursor_0ind(new_cur_pos)
end

function Node:set_from_rgrav(val)
	local pos = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, self.from, {})
	self.from = vim.api.nvim_buf_set_extmark(0, ns_id, pos[1], pos[2], {right_gravity = val})
end

function Node:set_to_rgrav(val)
	local pos = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, self.to, {})
	self.to = vim.api.nvim_buf_set_extmark(0, ns_id, pos[1], pos[2], {right_gravity = val})
end

local function mark_pos_equal(m1, m2)
	local p1 = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, m1, {})
	local p2 = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, m2, {})
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

function Node:get_text()
	local from = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, self.from, {})
	local to = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, self.to, {})

	-- end-exclusive indexing.
	local lines = vim.api.nvim_buf_get_lines(0, from[1], to[1]+1, false)

	if #lines == 1 then
		lines[1] = string.sub(lines[1], from[2]+1, to[2])
	else
		lines[1] = string.sub(lines[1], from[2]+1, #lines[1])

		-- node-range is end-exclusive.
		lines[#lines] = string.sub(lines[#lines], 1, to[2])
	end
	return lines
end

function Snippet:set_text(node, text)
	local node_from = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, node.from, {})
	local node_to = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, node.to, {})

	self:enter_node(node.indx)
	vim.api.nvim_buf_set_text(0, node_from[1], node_from[2], node_to[1], node_to[2], text)
end

function Snippet:exit()
	for _, node in ipairs(self.nodes) do
		vim.api.nvim_buf_del_extmark(0, ns_id, node.from)
		vim.api.nvim_buf_del_extmark(0, ns_id, node.to)
	end
	return self.parent
end

function Snippet:make_args(arglist)
	local args = {}
	for i, ins_id in ipairs(arglist) do
		args[i] = self.insert_nodes[ins_id]:get_text()
	end
	return args
end

function Snippet:update_fn_text(node)
	self:set_text(node, node.fn(self:make_args(node.args)))
end

-- jump(-1) on first insert would jump to end of snippet (0-insert).
local function jump(direction)
	local snip = active_snippet
	if snip == nil then
		return false
	end
	-- update text in dependents on leaving node.
	for _, node in ipairs(snip.insert_nodes[snip.current_insert].dependents) do
		snip:update_fn_text(node)
	end
	local tmp = snip.current_insert + direction
	-- Would jump to invalid node?
	if snip.insert_nodes[tmp] == nil then
		snip.current_insert = 0
	else
		snip.current_insert = tmp
	end

	snip:enter_node(snip.insert_nodes[snip.current_insert].indx)

	move_to_mark(snip.insert_nodes[snip.current_insert].from)
	if snip.current_insert == 0 then
		active_snippet = active_snippet:exit()
	end
	return true
end

-- delete n chars before cursor, MOVES CURSOR
local function remove_n_before_cur(n)
	local cur = get_cursor_0ind()
	vim.api.nvim_buf_set_text(0, cur[1], cur[2]-n, cur[1], cur[2], {""})
	cur[2] = cur[2]-n
	set_cursor_0ind(cur)
end

local function dump_active()
	for i, node in ipairs(active_snippet.nodes) do
		print(i)
		local c = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, node.from, {details = false})
		print(c[1], c[2])
		c = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, node.to, {details = false})
		print(c[1], c[2])
	end
end

function Snippet:expand()
	self.parent = active_snippet
	active_snippet = self

	-- Snippet is node, needs from and to.
	local cur = get_cursor_0ind()
	self.from = vim.api.nvim_buf_set_extmark(0, ns_id, cur[1], cur[2], {right_gravity = false})
	-- i needed for functions.
	for i, node in ipairs(self.nodes) do
		-- save cursor position for later.
		cur = get_cursor_0ind()

		-- Gravities are set 'pointing inwards' for static text, any text inserted on the border to a insert belongs
		-- to the insert.

		if node:has_static_text() then
			-- leaves cursor behind last char of inserted text.
			vim.api.nvim_put(node.static_text, "c", false, true);

			-- place extmark directly on previously saved position (first char
			-- of inserted text) after putting text.
			node.from = vim.api.nvim_buf_set_extmark(0, ns_id, cur[1], cur[2], {})
		else
			-- zero-length; important that text put after doesn't move marker.
			node.from = vim.api.nvim_buf_set_extmark(0, ns_id, cur[1], cur[2], {right_gravity = false})
		end

		cur = get_cursor_0ind()
		-- place extmark directly behind last char of put text.
		node.to = vim.api.nvim_buf_set_extmark(0, ns_id, cur[1], cur[2], {right_gravity = false})

		if node.type == 1 then
			self.insert_nodes[node.pos] = node
			-- do here as long as snippets need to be defined manually
			node.dependents = {}
		end
		-- do here as long as snippets need to be defined manually
		node.indx = i
	end

	cur = get_cursor_0ind()
	self.to = vim.api.nvim_buf_set_extmark(0, ns_id, cur[1], cur[2], {right_gravity = false})

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
	jump(1);
end

-- returns current line with text up-to and excluding the cursor.
local function get_current_line_to_cursor()
	local cur = get_cursor_0ind()
	-- cur-rows are 1-indexed, api-rows 0.
	local line = vim.api.nvim_buf_get_lines(0, cur[1], cur[1]+1, false)
	return string.sub(line[1], 1, cur[2])
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

-- return true and expand snippet if expandable, return false if not.
local function expand_or_jump()
	local line = get_current_line_to_cursor()
	local snip = match_snippet(line)
	if snip ~= nil then
		snip:indent(line)

		-- remove snippet-trigger, Cursor at start of future snippet text.
		remove_n_before_cur(#snip.trigger)

		snip:expand()
		return true
	end
	if active_snippet ~= nil then
		jump(1)
		return true
	end
	return false
end

return {
	expand_or_jump = expand_or_jump,
	jump = jump,
	snippets = snippets,
	i = i,
	t = t,
	f = f,
	dump_active = dump_active,
	get_active_snip = get_active_snip
}
