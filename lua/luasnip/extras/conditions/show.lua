local cond_obj = require("luasnip.extras.conditions")

local M = {}
-----------------------
-- PRESET CONDITIONS --
-----------------------
local function line_end(line_to_cursor)
	local line = vim.api.nvim_get_current_line()
	return #line_to_cursor == #line
end
M.line_end = cond_obj.make_condition(line_end)

return M
