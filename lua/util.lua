-- returns current line with text up-to and excluding the cursor.
function Get_current_line_to_cursor()
	local cur = Get_cursor_0ind()
	-- cur-rows are 1-indexed, api-rows 0.
	local line = vim.api.nvim_buf_get_lines(0, cur[1], cur[1]+1, false)
	return string.sub(line[1], 1, cur[2])
end

-- delete n chars before cursor, MOVES CURSOR
function Remove_n_before_cur(n)
	local cur = Get_cursor_0ind()
	vim.api.nvim_buf_set_text(0, cur[1], cur[2]-n, cur[1], cur[2], {""})
	cur[2] = cur[2]-n
	Set_cursor_0ind(cur)
end

function Move_to_mark(id)
	local new_cur_pos
	new_cur_pos = vim.api.nvim_buf_get_extmark_by_id(
		0, Ns_id, id, {details = false})
	Set_cursor_0ind(new_cur_pos)
end

function Set_cursor_0ind(c)
	c[1] = c[1] + 1
	vim.api.nvim_win_set_cursor(0, c)
end

function Get_cursor_0ind()
	local c = vim.api.nvim_win_get_cursor(0)
	c[1] = c[1] - 1
	return c
end

