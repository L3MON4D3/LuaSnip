-- used to store values like current nodes or the active node for autocommands.
local M = {}

M.ft_redirect = {}
setmetatable(M.ft_redirect, {
	__index = function(table, key)
		-- no entry for this ft(key), set it to avoid calls on each expand for
		-- this filetype.
		local val = { key }
		rawset(table, key, val)
		return val
	end,
})

M.current_nodes = {}
M.ns_id = vim.api.nvim_create_namespace("Luasnip")
-- only here for overview.
M.active_choice_node = nil

return M
