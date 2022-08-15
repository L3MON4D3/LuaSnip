local ls = require("luasnip")
local cache = require("luasnip.loaders._caches").snipmate
local util = require("luasnip.util.util")
local str_util = require("luasnip.util.str")
local loader_util = require("luasnip.loaders.util")
local Path = require("luasnip.util.path")
local session = require("luasnip.session")
local sp = require("luasnip.nodes.snippetProxy")

local function parse_snipmate(buffer, filename)
	-- could also be separate variables, but easier to access this way.
	local snippets = {
		snippet = {},
		autosnippet = {},
	}
	local extends = {}

	---@type string[]
	local lines = loader_util.split_lines(buffer)
	local i = 1

	local function _parse(snippet_type, snipmate_opts)
		local line = lines[i]
		-- "snippet" or "autosnippet"
		local prefix, description =
			line:match("^" .. snippet_type .. [[%s+(%S+)%s*(.*)]])
		local body = {}

		i = i + 1
		---@type number
		local indent

		while i <= #lines do
			line = lines[i]
			if line:find("^%s+") then
				if not indent then
					indent = #line:match("^%s+")
				end
				line = line:sub(indent + 1)
				line = line:gsub("${VISUAL}", "${TM_SELECTED_TEXT}")
			elseif line ~= "" then
				break
			end
			table.insert(body, line)
			i = i + 1
		end

		body = table.concat(body, "\n")
		local snip = sp({
			trig = prefix,
			dscr = description,
			wordTrig = true,
			priority = snipmate_opts.priority,
		}, body)
		table.insert(snippets[snippet_type], snip)
	end

	-- options for some snippet can be specified in the lines before the
	-- {auto}snippet-keyword ("priority 2000\nsnippet....").
	-- They are stored in snipmate_opts, which is cleaned whenever a snippet is
	-- actually created.
	local snipmate_opts = {}
	while i <= #lines do
		local line = lines[i]
		if vim.startswith(line, "snippet") then
			_parse("snippet", snipmate_opts)
			snipmate_opts = {}
		elseif vim.startswith(line, "autosnippet") then
			_parse("autosnippet", snipmate_opts)
			snipmate_opts = {}
		elseif vim.startswith(line, "extends") then
			extends = vim.split(vim.trim(line:sub(8)), "[,%s]+")
			i = i + 1
		elseif vim.startswith(line, "#") or line:find("^%s*$") then
			-- comment and blank line
			i = i + 1
		elseif vim.startswith(line, "priority") then
			snipmate_opts.priority = tonumber(line:match("priority%s+(%d+)"))
			i = i + 1
		else
			error(("invalid line in %s: %s"):format(filename, i))
		end
	end

	return snippets.snippet, snippets.autosnippet, extends
end

local function load_snippet_files(add_ft, paths, collection_files, add_opts)
	for _, path in ipairs(paths) do
		if not Path.exists(path) then
			return
		end

		local snippet, autosnippet, extends

		if cache.path_snippets[path] then
			snippet = vim.deepcopy(cache.path_snippets[path].snippet)
			autosnippet = vim.deepcopy(cache.path_snippets[path].autosnippet)
			extends = cache.path_snippets[path].extends
			cache.path_snippets[path].fts[add_ft] = true
		else
			local buffer = Path.read_file(path)
			snippet, autosnippet, extends = parse_snipmate(buffer, path)
			cache.path_snippets[path] = {
				snippet = vim.deepcopy(snippet),
				autosnippet = vim.deepcopy(autosnippet),
				extends = extends,
				-- store for reload.
				add_opts = add_opts,
				fts = {[add_ft] = true},
			}
		end

		ls.add_snippets(
			add_ft,
			snippet,
			vim.tbl_extend("keep", {
				type = "snippets",
				-- key has to include the filetype since one file may be loaded in
				-- multiple filetypes (via `extends`).
				key = string.format("__%s_snippets_%s", add_ft, path),
			}, add_opts)
		)
		ls.add_snippets(
			add_ft,
			autosnippet,
			vim.tbl_extend("keep", {
				type = "autosnippets",
				key = string.format("__%s_autosnippets_%s", add_ft, path),
			}, add_opts)
		)

		for _, ft in ipairs(extends) do
			load_snippet_files(
				add_ft,
				-- "or {}" because the ft might (if the extended filetype is not
				-- actually present in the collection) be nil.
				collection_files[ft] or {},
				collection_files,
				add_opts
			)
		end
	end
end

local M = {}

function M.load(opts)
	opts = opts or {}

	local add_opts = loader_util.add_opts(opts)

	-- we need all paths available in the collection for `extends`.
	-- only load_paths is influenced by in/exclude.
	local collections_load_paths =
		loader_util.get_load_paths_snipmate_like(opts, "snippets", "snippets")

	for _, collection in ipairs(collections_load_paths) do
		local load_paths = collection.load_paths
		local collection_paths = collection.collection_paths

		-- also add files from load_paths to cache (collection of all loaded
		-- files by filetype, useful for editing files for some filetype).
		loader_util.extend_ft_paths(cache.ft_paths, load_paths)

		for ft, paths in pairs(load_paths) do
			load_snippet_files(ft, paths, collection_paths, add_opts)
		end
	end
end

function M._load_lazy_loaded_ft(ft)
	for _, collection_load_paths in ipairs(cache.lazy_load_paths) do
		-- don't load if this ft wasn't included/was excluded.
		if collection_load_paths[ft] then
			load_snippet_files(
				ft,
				collection_load_paths[ft],
				collection_load_paths.collection,
				collection_load_paths.add_opts
			)
		end
	end
end

function M._load_lazy_loaded(bufnr)
	local fts = loader_util.get_load_fts(bufnr)

	for _, ft in ipairs(fts) do
		if not cache.lazy_loaded_ft[ft] then
			M._load_lazy_loaded_ft(ft)
			cache.lazy_loaded_ft[ft] = true
		end
	end
end

function M.lazy_load(opts)
	opts = opts or {}

	local add_opts = loader_util.add_opts(opts)

	local collections_load_paths =
		loader_util.get_load_paths_snipmate_like(opts, "snippets", "snippets")

	for _, collection in ipairs(collections_load_paths) do
		local load_paths = collection.load_paths
		local collection_paths = collection.collection_paths

		loader_util.extend_ft_paths(cache.ft_paths, load_paths)

		for ft, paths in pairs(load_paths) do
			if cache.lazy_loaded_ft[ft] then
				-- instantly load snippets if the ft is already loaded...
				load_snippet_files(ft, paths, collection_paths, add_opts)
				-- clear from load_paths to prevent duplicat loads.
				load_paths[ft] = nil
			end
		end

		load_paths.collection = collection_paths
		load_paths.add_opts = add_opts
		table.insert(cache.lazy_load_paths, load_paths)
	end

	-- load for current buffer on startup.
	M._load_lazy_loaded(vim.api.nvim_get_current_buf())
end

function M.edit_snippet_files()
	loader_util.edit_snippet_files(cache.ft_paths)
end

-- Make sure filename is normalized.
function M._reload_file(filename)
	local cached_data = cache.path_snippets[filename]
	if not cached_data then
		return
	end

	local add_opts = cached_data.add_opts
	cache.path_snippets[filename] = nil

	for ft, _ in pairs(cached_data.fts) do
		-- we can safely set collection to empty, the `extends` are already
		-- "set up", eg are included via cached_data.fts.
		load_snippet_files(ft, { filename }, {}, add_opts)

		ls.clean_invalidated({ inv_limit = 100 })
	end
end

return M
