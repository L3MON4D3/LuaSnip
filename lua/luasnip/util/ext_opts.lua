-- eventually turn ext_opts into proper objects, mainly for
-- default-construction eg. assured `complete`.
--
-- child_*-functions perform the same operation as theiry non-child
-- counterparts, but on a collection (eg.
-- `{[types.insertNode={...}, [types.textNode]= {...}]}`) of ext_opts.

local types = require("luasnip.util.types")

-- vim.tbl_extend always creates a new table, but doesn't accept nil, so we
-- always pass this empty table, which will (has to!) stay empty.
local shared_empty_table = {}

local states = {
	"active",
	"passive",
	"snippet_passive",
	"visited",
	"unvisited",
}

-- opts: child_ext_opts, have to have hl_group set for all combinations of
-- node-type and active,passive,snippet_passive,visited,unvisited.
local function clear_invalid(opts)
	--stylua: ignore start
	for _, node_type in pairs(types.node_types) do
		for _, state in ipairs(states) do
			local state_hl_group = opts[node_type][state].hl_group

			opts[node_type][state].hl_group =
				vim.fn.hlexists(state_hl_group) == 1 and state_hl_group
				                                      or nil
		end
	end
	--stylua: ignore end
end

local function _complete_ext_opts(ext_opts)
	if not ext_opts then
		ext_opts = {}
	end
	ext_opts.snippet_passive = ext_opts.snippet_passive or {}
	ext_opts.passive = vim.tbl_extend(
		"keep",
		ext_opts.passive or shared_empty_table,
		ext_opts.snippet_passive or shared_empty_table
	)
	-- both unvisited and visited inherit from passive.
	ext_opts.unvisited = vim.tbl_extend(
		"keep",
		ext_opts.unvisited or shared_empty_table,
		ext_opts.passive or shared_empty_table
	)
	ext_opts.visited = vim.tbl_extend(
		"keep",
		ext_opts.visited or shared_empty_table,
		ext_opts.passive or shared_empty_table
	)
	-- active inherits from visited.
	ext_opts.active = vim.tbl_extend(
		"keep",
		ext_opts.active or shared_empty_table,
		ext_opts.visited or shared_empty_table
	)

	for _, state in ipairs(states) do
		--stylua: ignore start
		if ext_opts[state].hl_group and not
		   ext_opts[state].priority then
			ext_opts[state].priority = 0
		end
		--stylua: ignore end
	end

	return ext_opts
end

-- active inherits unset values from passive, which in turn inherits from
-- snippet_passive.
-- Also make sure that all keys have a table, and are not nil!
local function child_complete(ext_opts)
	for _, node_type in pairs(types.node_types) do
		ext_opts[node_type] = _complete_ext_opts(ext_opts[node_type])
	end
	ext_opts.base_prio = 0

	return ext_opts
end

local function complete(ext_opts)
	_complete_ext_opts(ext_opts)
	ext_opts.base_prio = 0

	return ext_opts
end

-- in-place adds opts of b to a, doesn't override.
-- a/b: completed ext_opts, not nil.
local function extend(opts_a, opts_b)
	for _, state in ipairs(states) do
		opts_a[state] = vim.tbl_extend("keep", opts_a[state], opts_b[state])
	end

	return opts_a
end

-- in-place adds opts of b to a, doesn't override.
-- a/b: completed child_ext_opts, not nil.
local function child_extend(opts_a, opts_b)
	for _, node_type in ipairs(types.node_types) do
		extend(opts_a[node_type], opts_b[node_type])
	end

	return opts_a
end

local function increase_prio(opts, inc)
	-- increase only if there is a priority.
	for _, state in ipairs(states) do
		opts[state].priority = opts[state].priority
			and (opts[state].priority + inc)
	end
end

-- ext_opts-priorities are defined relative to some base-priority.
-- As nvim_api_buf_set_extmark takes absolute values only, we have to
-- set the absolute priorities, which can vary depending on nesting-level
-- of a given snippet, during runtime, by increasing the relative priorities by
-- either the conf.base_prio or the base-prio used in the previous nesting-level.
local function set_abs_prio(opts, new_base_prio)
	-- undo previous increase.
	-- base_prio is initialized with 0.
	local prio_offset = new_base_prio - opts.base_prio
	opts.base_prio = new_base_prio
	increase_prio(opts, prio_offset)

	return opts
end

local function child_set_abs_prio(opts, new_base_prio)
	-- undo previous increase.
	-- base_prio is initialized with 0.
	local prio_offset = new_base_prio - opts.base_prio
	opts.base_prio = new_base_prio
	for _, node_type in ipairs(types.node_types) do
		increase_prio(opts[node_type], prio_offset)
	end
	return opts
end

return {
	clear_invalid = clear_invalid,
	complete = complete,
	child_complete = child_complete,
	extend = extend,
	child_extend = child_extend,
	set_abs_prio = set_abs_prio,
	child_set_abs_prio = child_set_abs_prio,
}
