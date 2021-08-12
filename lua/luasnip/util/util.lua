local function get_cursor_0ind()
	local c = vim.api.nvim_win_get_cursor(0)
	c[1] = c[1] - 1
	return c
end

-- don't use utf-indexed column, win_set_cursor ignores these.
local function set_cursor_0ind(c)
	c[1] = c[1] + 1
	vim.api.nvim_win_set_cursor(0, c)
end

-- returns current line with text up-to and excluding the cursor.
local function get_current_line_to_cursor()
	local cur = get_cursor_0ind()
	-- cur-rows are 1-indexed, api-rows 0.
	local line = vim.api.nvim_buf_get_lines(0, cur[1], cur[1] + 1, false)
	return string.sub(line[1], 1, cur[2])
end

-- delete n chars before cursor, MOVES CURSOR
local function remove_n_before_cur(n)
	local cur = get_cursor_0ind()
	vim.api.nvim_buf_set_text(0, cur[1], cur[2] - n, cur[1], cur[2], { "" })
	cur[2] = cur[2] - n
	set_cursor_0ind(cur)
end

-- in-place modifies the table.
local function dedent(text, indentstring)
	-- 2 because 1 shouldn't contain indent.
	for i = 2, #text do
		text[i] = text[i]:gsub("^" .. indentstring, "")
	end
	return text
end

-- in-place insert indenstrig before each
local function indent(text, indentstring)
	for i = 2, #text do
		text[i] = text[i]:gsub("^", indentstring)
	end
	return text
end

local function expand_tabs(text)
	local tab_string = string.rep(
		" ",
		vim.o.shiftwidth ~= 0 and vim.o.shiftwidth or vim.o.tabstop
	)
	for i, str in ipairs(text) do
		text[i] = string.gsub(str, "\t", tab_string)
	end
end

local function mark_pos_equal(m1, m2)
	local p1 = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, m1, {})
	local p2 = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, m2, {})
	return p1[1] == p2[1] and p1[2] == p2[2]
end

local function move_to_mark(id)
	local new_cur_pos
	new_cur_pos = vim.api.nvim_buf_get_extmark_by_id(
		0,
		Luasnip_ns_id,
		id,
		{ details = false }
	)
	set_cursor_0ind(new_cur_pos)
end

local function bytecol_to_utfcol(pos)
	local line = vim.api.nvim_buf_get_lines(0, pos[1], pos[1] + 1, false)
	-- line[1]: get_lines returns table.
	return { pos[1], vim.str_utfindex(line[1], pos[2]) }
end

local function get_ext_positions(id)
	local mark_info = vim.api.nvim_buf_get_extmark_by_id(
		0,
		Luasnip_ns_id,
		id,
		{ details = true }
	)

	return bytecol_to_utfcol({ mark_info[1], mark_info[2] }),
		bytecol_to_utfcol({ mark_info[3].end_row, mark_info[3].end_col })
end

local function get_ext_position_begin(mark_id)
	local mark_info = vim.api.nvim_buf_get_extmark_by_id(
		0,
		Luasnip_ns_id,
		mark_id,
		{ details = false }
	)

	return bytecol_to_utfcol({ mark_info[1], mark_info[2] })
end

local function get_ext_position_end(id)
	local mark_info = vim.api.nvim_buf_get_extmark_by_id(
		0,
		Luasnip_ns_id,
		id,
		{ details = true }
	)

	return bytecol_to_utfcol({ mark_info[3].end_row, mark_info[3].end_col })
end

local function normal_move_before(new_cur_pos)
	-- +1: indexing
	if new_cur_pos[2] - 1 ~= 0 then
		vim.api.nvim_feedkeys(
			tostring(new_cur_pos[1] + 1)
				.. "G0"
				.. tostring(new_cur_pos[2] - 1)
				.. "l",
			"n",
			true
		)
	else
		vim.api.nvim_feedkeys(tostring(new_cur_pos[1] + 1) .. "G0", "n", true)
	end
end

local function normal_move_on(new_cur_pos)
	if new_cur_pos[2] ~= 0 then
		vim.api.nvim_feedkeys(
			tostring(new_cur_pos[1] + 1)
				.. "G0"
				.. tostring(new_cur_pos[2])
				.. "l",
			"n",
			true
		)
	else
		vim.api.nvim_feedkeys(tostring(new_cur_pos[1] + 1) .. "G0", "n", true)
	end
end

local function normal_move_on_insert(new_cur_pos)
	local keys = vim.api.nvim_replace_termcodes(
		tostring(new_cur_pos[1] + 1)
			.. "G0i"
			.. string.rep("<Right>", new_cur_pos[2]),
		true,
		false,
		true
	)
	vim.api.nvim_feedkeys(keys, "n", true)
end

local function multiline_equal(t1, t2)
	for i, line in ipairs(t1) do
		if line ~= t2[i] then
			return false
		end
	end

	return #t1 == #t2
end

local function word_under_cursor(cur, line)
	local ind_start = 1
	local ind_end = #line

	while true do
		local tmp = string.find(line, "%W%w", ind_start)
		if not tmp then
			break
		end
		if tmp > cur[2] + 1 then
			break
		end
		ind_start = tmp + 1
	end

	local tmp = string.find(line, "%w%W", cur[2] + 1)
	if tmp then
		ind_end = tmp
	end

	return string.sub(line, ind_start, ind_end)
end

-- Put text and update cursor(pos).
local function put(text, pos)
	vim.api.nvim_buf_set_text(0, pos[1], pos[2], pos[1], pos[2], text)
	-- add rows
	pos[1] = pos[1] + #text - 1
	-- add columns, start at 0 if no rows were added, else at old col-value.
	pos[2] = (#text > 1 and 0 or pos[2]) + #text[#text]
end

-- Wrap a value in a table if it isn't one already
local function wrap_value(value)
	if not value or type(value) == "table" then
		return value
	end
	return { value }
end

local SELECT_RAW = "LUASNIP_SELECT_RAW"
local SELECT_DEDENT = "LUASNIP_SELECT_DEDENT"
local TM_SELECT = "LUASNIP_TM_SELECT"

local function get_selection()
	local ok, val = pcall(vim.api.nvim_buf_get_var, 0, SELECT_RAW)
	-- if one is set, all are set.
	if ok then
		return val,
			vim.api.nvim_buf_get_var(0, SELECT_DEDENT),
			vim.api.nvim_buf_get_var(0, TM_SELECT)
	end
	-- not ok.
	return {}, {}, {}
end

local function get_min_indent(lines)
	-- "^(%s*)%S": match only lines that actually contain text.
	local min_indent = lines[1]:match("^(%s*)%S")
	for i = 2, #lines do
		-- %s* -> at least matches
		local line_indent = lines[i]:match("^(%s*)%S")
		if #line_indent < #min_indent then
			min_indent = line_indent
		end
	end
	return min_indent
end

local function store_selection()
	local start_line, start_col = vim.fn.line("'<"), vim.fn.col("'<")
	local end_line, end_col = vim.fn.line("'>"), vim.fn.col("'>")
	local mode = vim.fn.visualmode()
	if
		not vim.o.selection == "exclusive"
		and not (start_line == end_line and start_col == end_col)
	then
		end_col = end_col - 1
	end

	local chunks = {}
	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, true)
	if start_line == end_line then
		chunks = { lines[1]:sub(start_col, end_col) }
	else
		local first_col = 0
		local last_col = nil
		if mode:lower() ~= "v" then -- mode is block
			first_col = start_col
			last_col = end_col
		end
		chunks = { lines[1]:sub(start_col, last_col) }

		-- potentially trim lines (Block).
		for cl = 2, #lines - 1 do
			table.insert(chunks, lines[cl]:sub(first_col, last_col))
		end
		table.insert(chunks, lines[#lines]:sub(first_col, end_col))
	end

	-- init with raw selection.
	local tm_select, select_dedent = vim.deepcopy(chunks), vim.deepcopy(chunks)
	local min_indent = get_min_indent(lines)
	-- TM_SELECTED_TEXT contains text from new cursor position(for V the first
	-- non-whitespace of first line, v and c-v raw) to end of selection.
	if mode == "V" then
		tm_select[1] = tm_select[1]:gsub("^%s+", "")
		-- remove indent from all lines:
		for i = 1, #select_dedent do
			select_dedent[i] = select_dedent[i]:gsub("^" .. min_indent, "")
		end
	elseif mode == "v" then
		-- if selection starts inside indent, remove indent.
		if #min_indent > start_col then
			select_dedent[1] = lines[1]:gsub(min_indent, "")
		end
		for i = 2, #select_dedent - 1 do
			select_dedent[i] = select_dedent[i]:gsub(min_indent, "")
		end

		-- remove as much indent from the last line as possible.
		if #min_indent > end_col then
			select_dedent[#select_dedent] = ""
		else
			select_dedent[#select_dedent] = select_dedent[#select_dedent]:gsub(
				"^" .. min_indent,
				""
			)
		end
	else
		-- in block: if indent is in block, remove the part of it that is inside
		-- it for select_dedent.
		if #min_indent > start_col then
			local indent_in_block = min_indent:sub(start_col, #min_indent)
			for i, line in ipairs(chunks) do
				select_dedent[i] = line:gsub("^" .. indent_in_block, "")
			end
		end
	end

	vim.api.nvim_buf_set_var(0, SELECT_RAW, chunks)
	vim.api.nvim_buf_set_var(0, SELECT_DEDENT, select_dedent)
	vim.api.nvim_buf_set_var(0, TM_SELECT, tm_select)
end

local function pos_equal(p1, p2)
	return p1[1] == p2[1] and p1[2] == p2[2]
end

local function make_opts_valid(user_opts, default_opts, base_prio)
	local opts = vim.deepcopy(default_opts)
	for key, val in pairs(user_opts) do
		-- use raw default for passive if not given.
		val.passive = val.passive or default_opts[key].passive
		-- for active, add values from passive.
		val.active = vim.tbl_extend("keep", val.active or default_opts[key].active, val.passive)

		-- override copied default-value.
		opts[key] = val
	end
	return opts
end

local function increase_ext_prio(opts, amount)
	for _, val in pairs(opts) do
		val.active.priority = (val.active.priority or 0) + amount
		val.passive.priority = (val.passive.priority or 0) + amount
	end
	-- modifies in-place, but utilizing that may be cumbersome.
	return opts
end

return {
	get_cursor_0ind = get_cursor_0ind,
	set_cursor_0ind = set_cursor_0ind,
	get_ext_positions = get_ext_positions,
	get_ext_position_begin = get_ext_position_begin,
	get_ext_position_end = get_ext_position_end,
	move_to_mark = move_to_mark,
	normal_move_before = normal_move_before,
	normal_move_on = normal_move_on,
	normal_move_on_insert = normal_move_on_insert,
	remove_n_before_cur = remove_n_before_cur,
	get_current_line_to_cursor = get_current_line_to_cursor,
	mark_pos_equal = mark_pos_equal,
	multiline_equal = multiline_equal,
	word_under_cursor = word_under_cursor,
	put = put,
	wrap_value = wrap_value,
	store_selection = store_selection,
	get_selection = get_selection,
	pos_equal = pos_equal,
	dedent = dedent,
	indent = indent,
	expand_tabs = expand_tabs,
	make_opts_valid = make_opts_valid,
	increase_ext_prio = increase_ext_prio
}
