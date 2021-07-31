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
	return {pos[1], vim.str_utfindex(line[1], pos[2])}
end

local function get_ext_positions(id)
	local mark_info = vim.api.nvim_buf_get_extmark_by_id(
		0,
		Luasnip_ns_id,
		id,
		{ details = true }
	)

	return
		bytecol_to_utfcol({mark_info[1], mark_info[2]}),
		bytecol_to_utfcol({mark_info[3].end_row, mark_info[3].end_col})
end

local function get_ext_position_begin(mark_id)
	print(debug.traceback())
	local mark_info = vim.api.nvim_buf_get_extmark_by_id(
		0,
		Luasnip_ns_id,
		mark_id,
		{ details = false }
	)

	return bytecol_to_utfcol({mark_info[1], mark_info[2]})
end

local function get_ext_position_end(id)
	local mark_info = vim.api.nvim_buf_get_extmark_by_id(
		0,
		Luasnip_ns_id,
		id,
		{ details = true }
	)

	return bytecol_to_utfcol({mark_info[3].end_row, mark_info[3].end_col})
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

local LUASNIP_LAST_SELECTION = "LUASNIP_LAST_SELECTION"

local function get_selection()
	local ok, val = pcall(vim.api.nvim_buf_get_var, 0, LUASNIP_LAST_SELECTION)
	return ok and val or ""
end

local function store_selection()
	local chunks = vim.split(vim.fn.getreg('"'), "\n")
	vim.api.nvim_buf_set_var(0, LUASNIP_LAST_SELECTION, chunks)
end

local function pos_equal(p1, p2)
	return p1[1] == p2[1] and p1[2] == p2[2]
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
	pos_equal = pos_equal
}
