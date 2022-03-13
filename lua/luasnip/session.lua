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
M.latest_load_ft = nil

M.last_expand_snip = nil
M.last_expand_opts = nil

-- jump_active is set while luasnip moves the cursor, prevents
-- (for example) updating dependents or deleting a snippet via
-- exit_out_of_region while jumping.
-- init with false, it will be set by (eg.) ls.jump().
M.jump_active = false

M.config = nil

M.invalidated_count = 0

-- store snippets by some key.
M.by_key = {}

-- stores snippets/autosnippets by priority.
M.by_prio = {
	snippets = {
		-- stores sorted keys, eg 1=1000, 2=1010, 3=1020,..., used for
		-- quick iterating.
		order = {
			1000,
		},
		[1000] = {
			all = {},
		},
	},
	autosnippets = {
		order = {
			1000,
		},
		[1000] = {
			all = {},
		},
	},
}

-- this isn't in util/util.lua due to circular dependencies. Would be cleaner
-- to include it there, but it's alright to keep here for now.
--
-- this is linear, binary search would certainly be nicer, but for our
-- applications this should easily be enough.
local function insert_sorted_unique(t, k)
	local tbl_len = #t

	local i = 1
	-- k does not yet exist in table, find first i so t[i] > k.
	for _ = 1, tbl_len do
		if t[i] > k then
			break
		end
		i = i + 1
	end

	-- shift all t[j] with j > i back by one.
	for j = tbl_len, i, -1 do
		t[j + 1] = t[j]
	end

	t[i] = k
end

local sort_mt = {
	__newindex = function(t, k, v)
		-- update priority-order as well.
		insert_sorted_unique(t.order, k)
		rawset(t, k, v)
	end,
}

setmetatable(M.by_prio.snippets, sort_mt)
setmetatable(M.by_prio.autosnippets, sort_mt)

return M
