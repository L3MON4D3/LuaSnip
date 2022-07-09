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

-- opts: child_ext_opts, have to have hl_group set for all combinations of
-- node-type and active,passive,snippet_passive.
local function clear_invalid(opts)
	for _, node_type in pairs(types.node_types) do
		local act_group, pas_group, snip_pas_group =
			opts[node_type].active.hl_group,
			opts[node_type].passive.hl_group,
			opts[node_type].snippet_passive.hl_group

		--stylua: ignore start
		opts[node_type].snippet_passive.hl_group =
			vim.fn.hlexists(snip_pas_group) == 1 and snip_pas_group
			or nil
		opts[node_type].passive.hl_group =
			vim.fn.hlexists(pas_group) == 1 and pas_group
			or nil
		opts[node_type].active.hl_group =
			vim.fn.hlexists(act_group) == 1 and act_group
			or nil
		--stylua: ignore end
	end
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
	ext_opts.active = vim.tbl_extend(
		"keep",
		ext_opts.active or shared_empty_table,
		ext_opts.passive or shared_empty_table
	)

	--stylua: ignore start
	if ext_opts.snippet_passive.hl_group and not
	   ext_opts.snippet_passive.priority then
		ext_opts.snippet_passive.priority = 0
	end

	if ext_opts.passive.hl_group and not
	   ext_opts.passive.priority then
		ext_opts.passive.priority = 0
	end

	if ext_opts.active.hl_group and not
	   ext_opts.active.priority then
		ext_opts.active.priority = 0
	end
	--stylua: ignore end

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
	opts_a.snippet_passive =
		vim.tbl_extend("keep", opts_a.snippet_passive, opts_b.snippet_passive)
	opts_a.passive = vim.tbl_extend("keep", opts_a.passive, opts_b.passive)
	opts_a.active = vim.tbl_extend("keep", opts_a.active, opts_b.active)

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
	opts.active.priority = opts.active.priority and (opts.active.priority + inc)

	opts.passive.priority = opts.passive.priority
		and (opts.passive.priority + inc)

	opts.snippet_passive.priority = opts.snippet_passive.priority
		and (opts.snippet_passive.priority + inc)
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
