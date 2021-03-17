local active_snippet = nil
local ns_id = vim.api.nvim_create_namespace("luasnip")

local function get_active_snip() return active_snippet end

local snippets = {
	{
		trigger = "fn",
		nodes = {
			{
				type = 0,
				static_text = {"function "},
			},
			{
				type = 1,
				static_text = {""},
				pos = 1,
				dependents = {}
			},
			{
				type = 0,
				static_text = {"("},
			},
			{
				type = 1,
				static_text = {""},
				pos = 2,
				dependents = {}
			},
			{
				type = 0,
				static_text = {") {","\t"},
			},
			{
				type = 1,
				static_text = {""},
				pos = 0,
				dependents = {}
			},
			{
				type = 0,
				static_text = {"", "}"}
			},
		},
		insert_nodes = {},
		current_insert = 0,
		parent = nil
	}
}

local function get_cursor_0ind()
	local c = vim.api.nvim_win_get_cursor(0)
	c[1] = c[1] - 1
	return c
end

local function set_cursor_0ind(c)
	c[1] = c[1] + 1
	vim.api.nvim_win_set_cursor(0, c)
	return c
end

-- returns snippet-object where its trigger matches the end of the line, nil if no match.
local function match_snippet(line)
	for i = 1, #snippets do
		local snip = snippets[i]
		-- if line ends with trigger
		if string.sub(line, #line - #snip.trigger + 1, #line) == snip.trigger then
			return vim.deepcopy(snip)
		end
	end
	return nil
end

local function has_static_text(node)
	return not (node.static_text[1] == "" and #node.static_text == 1)
end

local function move_to_mark(id)
	local new_cur_pos
	new_cur_pos = vim.api.nvim_buf_get_extmark_by_id(
		0, ns_id, id, {details = false})
	set_cursor_0ind(new_cur_pos)
end

local function set_from_rgrav(node, val)
	local pos = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, node.from, {})
	node.from = vim.api.nvim_buf_set_extmark(0, ns_id, pos[1], pos[2], {right_gravity = val})
end

local function set_to_rgrav(node, val)
	local pos = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, node.to, {})
	node.to = vim.api.nvim_buf_set_extmark(0, ns_id, pos[1], pos[2], {right_gravity = val})
end

local function enter_node(snip, node_id)
	for i = 1, node_id-1, 1 do
		if snip.nodes[i].type == 1 then
			set_from_rgrav(snip.nodes[i], false)
			set_to_rgrav(snip.nodes[i], false)
		end
	end
	set_from_rgrav(snip.nodes[node_id], false)
	set_to_rgrav(snip.nodes[node_id], true)
	for i = node_id+1, #snip.nodes, 1 do
		if snip.nodes[i].type == 1 then
			set_from_rgrav(snip.nodes[i], true)
			set_to_rgrav(snip.nodes[i], true)
		end
	end
end

local function exit_snip()
	active_snippet = nil
end

-- jump(-1) on first insert would jump to end of snippet (0-insert).
local function jump(direction)
	local snip = active_snippet
	if snip == nil then
		return false
	end
	local tmp = snip.current_insert + direction
	-- Would jump to invalid node?
	if snip.insert_nodes[tmp] == nil then
		snip.current_insert = 0
	else
		snip.current_insert = tmp
	end

	enter_node(snip, snip.insert_nodes[snip.current_insert].indx)

	move_to_mark(snip.insert_nodes[snip.current_insert].from)
	if snip.current_insert == 0 then
		exit_snip()
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

local function next_with_text(snip, node_ind)
	for i = node_ind + 1, #snip.nodes do
		if has_static_text(snip.nodes[i]) then
			return i
		end
	end
	return nil
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

local function expand(snip)
	active_snippet = snip

	-- remove snippet-trigger, Cursor at start of future snippet text.
	local triglen = #snip.trigger;
	remove_n_before_cur(triglen)

	-- i needed for functions.
	for i, node in ipairs(snip.nodes) do
		-- save cursor position for later.
		local cur = get_cursor_0ind()

		-- place extmark directly on previously saved position (first char
		-- of inserted text) after putting text.
		node.from = vim.api.nvim_buf_set_extmark(0, ns_id, cur[1], cur[2], {right_gravity = false})

		if has_static_text(node) then
			-- leaves cursor behind last char of inserted text.
			vim.api.nvim_put(node.static_text, "c", false, true);
		end

		cur = get_cursor_0ind()
		-- place extmark directly behind last char of put text.
		node.to = vim.api.nvim_buf_set_extmark(0, ns_id, cur[1], cur[2], {right_gravity = false})

		if node.type == 1 then
			snip.insert_nodes[node.pos] = node
		end
		node.indx = i
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

local function indent(snip, line)
	local prefix = string.match(line, '^%s*')
	for _, node in ipairs(snip.nodes) do
		-- put prefix behind newlines.
		for i = 2, #node.static_text do
			node.static_text[i] = prefix .. node.static_text[i]
		end
	end
end

-- return true and expand snippet if expandable, return false if not.
local function expand_or_jump()
	if active_snippet ~= nil then
		jump(1)
		return true
	end
	local line = get_current_line_to_cursor()
	local snip = match_snippet(line)
	if snip ~= nil then
		indent(snip, line)
		expand(snip)
		return true
	end
	return false
end

return {
	expand_or_jump = expand_or_jump,
	next_with_text = next_with_text,
	has_static_text = has_static_text,
	get_active_snip = get_active_snip,
	dump_active = dump_active
}
