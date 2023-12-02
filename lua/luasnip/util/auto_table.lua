-- depth specifies how many levels under this table should be allowed to index
-- throug this metamethod
-- set depth to 0 to disable checking
-- Acknowledgment: This is (maybe more than) inspired by
-- https://lua-users.org/wiki/AutomagicTables so special thanks to
-- Thomas Wrensch and Rici Lake for sharing their ideas on this topic.
local function auto_creating_tables_warn_depth(self, key, depth)
	local t = {}
	assert(depth ~= 1, "don't index at that level")
	setmetatable(t, {
		-- creating a new function on each time (could be shared) isn't that
		-- nice. Nonetheless this shouldn't be too bad, as these are only
		-- created twice (auto+snippet) per ft and twice for each prio,ft
		-- combination
		__index = function(s, k)
			return auto_creating_tables_warn_depth(s, k, depth - 1)
		end,
	})
	self[key] = t
	return t
end

local function auto_creating_tables(self, key, depth)
	local t = {}
	if depth ~= 1 then
		setmetatable(t, {
			__index = function(s, k)
				return auto_creating_tables(s, k, depth - 1)
			end,
		})
	end
	self[key] = t
	return t
end

local M = {}

function M.autotable(max_depth, opts)
	opts = opts or {}
	local warn = vim.F.if_nil(opts.warn, false)

	local auto_table_func = warn and auto_creating_tables_warn_depth
		or auto_creating_tables

	return setmetatable({}, {
		__index = function(s, k)
			return auto_table_func(s, k, max_depth - 1)
		end,
	})
end

M.warn_depth_autotable = auto_creating_tables_warn_depth

return M
