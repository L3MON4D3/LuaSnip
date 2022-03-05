-- eventually turn ext_opts into proper objects, mainly for
-- default-construction eg. assured `complete`.

local types = require("luasnip.util.types")

-- vim.tbl_extend always creates a new table, but doesn't accept nil, so we
-- always pass this empty table, which will (has to!) stay empty.
local shared_empty_table = {}

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

-- active inherits unset values from passive, which in turn inherits from
-- snippet_passive.
-- Also make sure that all keys have a table, and are not nil!
local function complete(ext_opts)
	ext_opts.increased_by = 0
	for _, node_type in pairs(types.node_types) do
		local node_opts
		if not ext_opts[node_type] then
			node_opts = {}
			ext_opts[node_type] = node_opts
		else
			node_opts = ext_opts[node_type]
		end
		node_opts.snippet_passive = node_opts.snippet_passive or {}
		node_opts.passive = vim.tbl_extend(
			"keep",
			node_opts.passive or shared_empty_table,
			node_opts.snippet_passive or shared_empty_table
		)
		node_opts.active = vim.tbl_extend(
			"keep",
			node_opts.active or shared_empty_table,
			node_opts.passive or shared_empty_table
		)

		--stylua: ignore start
		if node_opts.snippet_passive.hl_group and not
		   node_opts.snippet_passive.priority then
			node_opts.snippet_passive.priority = 0
		end

		if node_opts.passive.hl_group and not
		   node_opts.passive.priority then
			node_opts.passive.priority = 0
		end

		if node_opts.active.hl_group and not
		   node_opts.active.priority then
			node_opts.active.priority = 0
		end
		--stylua: ignore end
	end
end

-- in-place adds opts of b to a, doesn't override.
-- a/b: completed ext_opts, not nil.
local function extend(opts_a, opts_b)
	for _, node_type in ipairs(types.node_types) do
		local node_opts_a = opts_a[node_type]
		local node_opts_b = opts_b[node_type]

		node_opts_a.snippet_passive = vim.tbl_extend(
			"keep",
			node_opts_a.snippet_passive,
			node_opts_b.snippet_passive
		)
		node_opts_a.passive = vim.tbl_extend(
			"keep",
			node_opts_a.passive,
			node_opts_b.passive
		)
		node_opts_a.active = vim.tbl_extend(
			"keep",
			node_opts_a.active,
			node_opts_b.active
		)
	end
end

-- ext_opts-priorities are defined relative to some base-priority.
-- As nvim_api_buf_set_extmark takes absolute values only, we have to
-- set the absolute priorities, which can vary depending on nesting-level
-- of a given snippet, during runtime, by increasing the relative priorities by
-- either the conf.base_prio or the base-prio used in the previous nesting-level.
local function increase_prio(opts, amount)
	opts.increased_by = opts.increased_by + amount
	for _, node_type in pairs(types.node_types) do
		local node_opts = opts[node_type]
		node_opts.active.priority = node_opts.active.priority
			and node_opts.active.priority + amount

		node_opts.passive.priority = node_opts.passive.priority
			and node_opts.passive.priority + amount

		node_opts.snippet_passive.priority = node_opts.snippet_passive.priority
			and node_opts.snippet_passive.priority + amount
	end
	-- modifies in-place, but utilizing that may be cumbersome.
	return opts
end

return {
	clear_invalid = clear_invalid,
	complete = complete,
	extend = extend,
	increase_prio = increase_prio,
}
