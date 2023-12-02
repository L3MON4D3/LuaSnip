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
-- roots of snippet-trees, per-buffer.
-- snippet_roots[n] => list of snippet-roots in buffer n.
M.snippet_roots = setmetatable({}, {
	-- create missing lists automatically.
	__index = function(t, k)
		local new_t = {}
		rawset(t, k, new_t)
		return new_t
	end,
})
M.ns_id = vim.api.nvim_create_namespace("Luasnip")
M.active_choice_nodes = {}

-- only here for overview.
M.latest_load_ft = nil

M.last_expand_snip = nil
M.last_expand_opts = nil

-- jump_active is set while luasnip moves the cursor, prevents
-- (for example) updating dependents or deleting a snippet via
-- exit_out_of_region while jumping.
-- init with false, it will be set by (eg.) ls.jump().
M.jump_active = false

-- initial value, might be overwritten immediately.
-- No danger of overwriting user-config, since this has to be loaded to allow
-- overwriting.
M.config = require("luasnip.default_config")

M.loaded_fts = {}

function M.get_snip_env()
	return M.config.snip_env
end

return M
