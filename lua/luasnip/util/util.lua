local function get_cursor_0ind()
	local c = vim.api.nvim_win_get_cursor(0)
	c[1] = c[1] - 1
	return c
end

local function set_cursor_0ind(c)
	c[1] = c[1] + 1
	vim.api.nvim_win_set_cursor(0, c)
end

-- returns current line with text up-to and excluding the cursor.
local function get_current_line_to_cursor()
	local cur = get_cursor_0ind()
	-- cur-rows are 1-indexed, api-rows 0.
	local line = vim.api.nvim_buf_get_lines(0, cur[1], cur[1]+1, false)
	return string.sub(line[1], 1, cur[2])
end

-- delete n chars before cursor, MOVES CURSOR
local function remove_n_before_cur(n)
	local cur = get_cursor_0ind()
	vim.api.nvim_buf_set_text(0, cur[1], cur[2]-n, cur[1], cur[2], {""})
	cur[2] = cur[2]-n
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
		0, Luasnip_ns_id, id, {details = false})
	set_cursor_0ind(new_cur_pos)
end

local function get_ext_position(id)
	local cur = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, id, {details = false})
	local line = vim.api.nvim_buf_get_lines(0, cur[1], cur[1]+1, false)
	cur[2] = vim.str_utfindex(line[1], cur[2])
	return cur
end

local function normal_move_before_mark(id)
	local new_cur_pos = get_ext_position(id)
	-- +1: indexing
	if new_cur_pos[2]-1 ~= 0 then
		vim.api.nvim_feedkeys(tostring(new_cur_pos[1]+1)..'G0'..tostring(new_cur_pos[2]-1)..'l', 'n', true)
	else
		vim.api.nvim_feedkeys(tostring(new_cur_pos[1]+1)..'G0', 'n', true)
	end
end

local function normal_move_on_mark(id)
	local new_cur_pos = get_ext_position(id)
	if new_cur_pos[2] ~= 0 then
		vim.api.nvim_feedkeys(tostring(new_cur_pos[1]+1)..'G0'..tostring(new_cur_pos[2])..'l', 'n', true)
	else
		vim.api.nvim_feedkeys(tostring(new_cur_pos[1]+1)..'G0', 'n', true)
	end
end

local function normal_move_on_mark_insert(id)
	local new_cur_pos = get_ext_position(id)
	local keys = vim.api.nvim_replace_termcodes(
		tostring(new_cur_pos[1]+1)..'G0i'..string.rep('<Right>', new_cur_pos[2]), true, false, true)
	vim.api.nvim_feedkeys(keys, 'n', true)
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
		if tmp > cur[2]+1 then
			break
		end
		ind_start = tmp+1
	end

	local tmp = string.find(line, "%w%W", cur[2]+1)
	if tmp then
		ind_end = tmp
	end

	return string.sub(line, ind_start, ind_end)
end

return {
	get_cursor_0ind = get_cursor_0ind,
	set_cursor_0ind = set_cursor_0ind,
	get_ext_position = get_ext_position,
	move_to_mark = move_to_mark,
	normal_move_before_mark = normal_move_before_mark,
	normal_move_on_mark = normal_move_on_mark,
	normal_move_on_mark_insert = normal_move_on_mark_insert,
	remove_n_before_cur = remove_n_before_cur,
	get_current_line_to_cursor = get_current_line_to_cursor,
	mark_pos_equal = mark_pos_equal,
	multiline_equal = multiline_equal,
	word_under_cursor = word_under_cursor
}
