local M = {}

function M.line_begin(line_to_cursor, matched_trigger)
	-- +1 because `string.sub("abcd", 1, -2)` -> abc
	return line_to_cursor:sub(1, -(#matched_trigger + 1)):match("^%s*$")
end

function M.line_end(line_to_cursor)
	local line = vim.api.nvim_get_current_line()
	return #line_to_cursor == #line
end

return M
