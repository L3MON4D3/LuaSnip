-- used to store values like current nodes or the active node for autocommands.
local M = {}

M.ft_redirect = {}
setmetatable(M.ft_redirect, {
	__index = function(table, key)
		-- no entry for this ft(key), set it to avoid calls on each expand for
		-- this filetype.
		rawset(table, key, { key })
		return { key }
	end,
})

return M
