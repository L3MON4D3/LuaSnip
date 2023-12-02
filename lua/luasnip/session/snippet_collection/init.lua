local source = require("luasnip.session.snippet_collection.source")
local u_table = require("luasnip.util.table")
local auto_creating_tables =
	require("luasnip.util.auto_table").warn_depth_autotable
local session = require("luasnip.session")

-- store snippets by some key.
-- also ordered by filetype, eg.
-- {
--	key = {
--		ft1 = {...},
--		ft2 = {...}
--	}
-- }
local M = {
	invalidated_count = 0,
}

local by_key = {}

-- stores snippets/autosnippets by priority.
local by_prio = {
	snippets = {
		-- stores sorted keys, eg 1=1000, 2=1010, 3=1020,..., used for
		-- quick iterating.
		order = {},
	},
	autosnippets = {
		order = {},
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

local by_prio_snippets_mt = {
	__index = function(s, k)
		-- make new tables as they are indexed
		return auto_creating_tables(s, k, 3)
	end,
	__newindex = function(t, k, v)
		-- update priority-order as well.
		insert_sorted_unique(t.order, k)
		rawset(t, k, v)
	end,
}
-- metatable for the by_prio table used when by_prio.type[prio] is reset
-- create here so that it can be shared and only has to be created once
local prio_mt2 = {
	__index = function(s, k)
		-- make new tables as they are indexed
		return auto_creating_tables(s, k, 2)
	end,
}

setmetatable(by_prio.snippets, by_prio_snippets_mt)
setmetatable(by_prio.autosnippets, by_prio_snippets_mt)

-- iterate priorities, high to low.
local function prio_iter(type)
	local order = by_prio[type].order
	local i = #order + 1

	return function()
		i = i - 1
		if i > 0 then
			return by_prio[type][order[i]]
		end
		return nil
	end
end

local by_ft = {
	snippets = {},
	autosnippets = {},
}

local by_ft_snippets_mt = {
	__index = function(s, k)
		return auto_creating_tables(s, k, 2)
	end,
}
setmetatable(by_ft.snippets, by_ft_snippets_mt)
setmetatable(by_ft.autosnippets, by_ft_snippets_mt)

local by_id = setmetatable({}, {
	-- make by_id-table weak (v).
	-- this means it won't be necessary to explicitly nil values (snippets) in
	-- this table.
	__mode = "v",
})

-- ft: any filetype, optional.
function M.clear_snippets(ft)
	if ft then
		-- remove all ft-(auto)snippets for all priorities.
		-- set to empty table so we won't need to rebuild/clear the order-table.
		for _, prio in ipairs(by_prio.snippets.order) do
			by_prio.snippets[prio][ft] = {}
		end
		for _, prio in ipairs(by_prio.autosnippets.order) do
			by_prio.autosnippets[prio][ft] = {}
		end

		by_ft.snippets[ft] = nil
		by_ft.autosnippets[ft] = nil

		for key, _ in pairs(by_key) do
			by_key[key][ft] = nil
		end
	else
		-- remove all (auto)snippets for all priorities.
		for _, prio in ipairs(by_prio.snippets.order) do
			by_prio.snippets[prio] = {}
			setmetatable(by_prio.snippets[prio], prio_mt2)
		end
		for _, prio in ipairs(by_prio.autosnippets.order) do
			by_prio.autosnippets[prio] = {}
			setmetatable(by_prio.autosnippets[prio], prio_mt2)
		end

		by_key = {}
		by_ft.snippets = {}
		setmetatable(by_ft.snippets, by_ft_snippets_mt)
		by_ft.autosnippets = {}
		setmetatable(by_ft.autosnippets, by_ft_snippets_mt)
	end
end

function M.match_snippet(line, fts, type)
	local expand_params

	for prio_by_ft in prio_iter(type) do
		for _, ft in ipairs(fts) do
			for _, snip in ipairs(prio_by_ft[ft] or {}) do
				expand_params = snip:matches(line)
				if expand_params then
					-- return matching snippet and table with expand-parameters.
					return snip, expand_params
				end
			end
		end
	end

	return nil
end

local function without_invalidated(snippets_by_ft)
	local new_snippets = {}

	for ft, ft_snippets in pairs(snippets_by_ft) do
		new_snippets[ft] = {}
		for _, snippet in ipairs(ft_snippets) do
			if not snippet.invalidated then
				table.insert(new_snippets[ft], snippet)
			end
		end
	end

	return new_snippets
end

function M.clean_invalidated(opts)
	if opts.inv_limit then
		if M.invalidated_count <= opts.inv_limit then
			return
		end
	end

	-- remove invalidated snippets from all tables.
	for _, type_snippets in pairs(by_prio) do
		for key, prio_snippets in pairs(type_snippets) do
			if key ~= "order" then
				type_snippets[key] = without_invalidated(prio_snippets)
				setmetatable(type_snippets[key], prio_mt2)
			end
		end
	end

	for type, type_snippets in pairs(by_ft) do
		by_ft[type] = without_invalidated(type_snippets)
		setmetatable(by_ft[type], by_ft_snippets_mt)
	end

	for key, key_snippets in pairs(by_key) do
		by_key[key] = without_invalidated(key_snippets)
	end

	M.invalidated_count = 0
end

local function invalidate_addables(addables_by_ft)
	for _, addables in pairs(addables_by_ft) do
		for _, addable in ipairs(addables) do
			for _, expandable in ipairs(addable:retrieve_all()) do
				expandable:invalidate()
			end
		end
	end
	M.clean_invalidated({ inv_limit = 100 })
end

local current_id = 0
-- snippets like {ft1={<snippets>}, ft2={<snippets>}}, opts should be properly
-- initialized with default values.
function M.add_snippets(snippets, opts)
	for ft, ft_snippets in pairs(snippets) do
		for _, addable in ipairs(ft_snippets) do
			for _, snip in ipairs(addable:retrieve_all()) do
				local snip_prio = opts.override_priority
					or (snip.priority and snip.priority)
					or opts.default_priority
					or 1000

				-- if snippetType undefined by snippet, take default value from opts
				local snip_type = snip.snippetType ~= nil and snip.snippetType
					or opts.type
				assert(
					snip_type == "autosnippets" or snip_type == "snippets",
					"snippetType must be either 'autosnippets' or 'snippets', was "
						.. vim.inspect(snip_type)
				)

				local snip_ft = snip.filetype or ft

				snip.id = current_id
				current_id = current_id + 1

				-- do the insertion
				table.insert(by_prio[snip_type][snip_prio][snip_ft], snip)
				table.insert(by_ft[snip_type][snip_ft], snip)
				by_id[snip.id] = snip

				-- set source if it is available.
				if snip._source then
					source.set(snip, snip._source)
				end
			end
		end
	end

	if opts.key then
		if by_key[opts.key] then
			invalidate_addables(by_key[opts.key])
		end
		by_key[opts.key] = snippets
	end
end

-- specialized copy functions to not loose performance on ifs when copying
-- and to be able to specify when pairs or ipairs is used
local function copy_by_ft_type_ft(tab)
	local r = {}
	for k, v in ipairs(tab) do
		r[k] = v
	end
	return r
end
local function copy_by_ft_type(tab)
	local r = {}
	for k, v in pairs(tab) do
		r[k] = copy_by_ft_type_ft(v)
	end
	return r
end

-- ft may be nil, type not.
function M.get_snippets(ft, type)
	if ft then
		return copy_by_ft_type_ft(by_ft[type][ft])
	else
		return copy_by_ft_type(by_ft[type])
	end
end

function M.get_id_snippet(id)
	return by_id[id]
end

local function get_all_snippet_fts()
	local ft_set = {}
	for ft, _ in pairs(by_ft.snippets) do
		ft_set[ft] = true
	end
	for ft, _ in pairs(by_ft.autosnippets) do
		ft_set[ft] = true
	end

	return u_table.set_to_list(ft_set)
end

-- modules that want to call refresh_notify probably also want to notify others
-- of adding those snippets => put those functions into the same module.
function M.refresh_notify(ft_or_nil)
	local fts = ft_or_nil and { ft_or_nil } or get_all_snippet_fts()

	for _, ft in ipairs(fts) do
		session.latest_load_ft = ft
		vim.api.nvim_exec_autocmds(
			"User",
			{ pattern = "LuasnipSnippetsAdded", modeline = false }
		)
	end
end

return M
