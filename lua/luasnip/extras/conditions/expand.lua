local cond_obj = require("luasnip.extras.conditions")

-- use the functions from show as basis and extend/overwrite functions specific for expand here
local M = vim.deepcopy(require("luasnip.extras.conditions.show"))
-----------------------
-- PRESET CONDITIONS --
-----------------------
local function line_begin(line_to_cursor, matched_trigger)
	-- +1 because `string.sub("abcd", 1, -2)` -> abc
	return line_to_cursor:sub(1, -(#matched_trigger + 1)):match("^%s*$")
end
M.line_begin = cond_obj.make_condition(line_begin)

return M
