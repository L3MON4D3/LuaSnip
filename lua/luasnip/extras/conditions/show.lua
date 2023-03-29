local cond_obj = require("luasnip.extras.conditions")

local M = {}
-----------------------
-- PRESET CONDITIONS --
-----------------------
local function line_end(line_to_cursor)
	local line = vim.api.nvim_get_current_line()
	-- looks pretty inefficient, but as lue interns strings, this is just a
	-- comparision of pointers (which probably is faster than calculate the
	-- length and then checking)
	return line_to_cursor == line
end
M.line_end = cond_obj.make_condition(line_end)

local function has_selected_text()
	return vim.b.LUASNIP_TM_SELECT ~= nil
end
M.has_selected_text = cond_obj.make_condition(has_selected_text)

return M
