local ls = require("luasnip")
local cache = require("luasnip.loaders._caches").vscode
local util = require("luasnip.util.util")
local str_util = require("luasnip.util.str")
local loader_util = require("luasnip.loaders.util")
local Path = require("luasnip.util.path")
local sp = require("luasnip.nodes.snippetProxy")

local function json_decode(data)
	local status, result = pcall(util.json_decode, data)
	if status then
		return result
	else
		return nil, result
	end
end

local function get_file_snippets(file)
	local lang_snips = {}
	local auto_lang_snips = {}

	local data = Path.read_file(file)
	local snippet_set_data = json_decode(data)
	if snippet_set_data == nil then
		return
	end

	for name, parts in pairs(snippet_set_data) do
		local body = type(parts.body) == "string" and parts.body
			or table.concat(parts.body, "\n")

		-- There are still some snippets that fail while loading
		pcall(function()
			-- Sometimes it's a list of prefixes instead of a single one
			local prefixes = type(parts.prefix) == "table" and parts.prefix
				or { parts.prefix }
			for _, prefix in ipairs(prefixes) do
				local ls_conf = parts.luasnip or {}

				local snip = sp({
					trig = prefix,
					name = name,
					dscr = parts.description or name,
					wordTrig = true,
					priority = ls_conf.priority,
				}, body)

				if ls_conf.autotrigger then
					table.insert(auto_lang_snips, snip)
				else
					table.insert(lang_snips, snip)
				end
			end
		end)
	end

	return lang_snips, auto_lang_snips
end

local function load_snippet_files(lang, files, add_opts)
	for _, file in ipairs(files) do
		if Path.exists(file) then
			local lang_snips, auto_lang_snips

			local cached_path = cache.path_snippets[file]
			if cached_path then
				lang_snips = vim.deepcopy(cached_path.snippets)
				auto_lang_snips = vim.deepcopy(cached_path.autosnippets)
				cached_path.fts[lang] = true
			else
				lang_snips, auto_lang_snips = get_file_snippets(file)
				-- store snippets to prevent parsing the same file more than once.
				cache.path_snippets[file] = {
					snippets = vim.deepcopy(lang_snips),
					autosnippets = vim.deepcopy(auto_lang_snips),
					add_opts = add_opts,
					fts = { [lang] = true},
				}
			end

			ls.add_snippets(
				lang,
				lang_snips,
				vim.tbl_extend("keep", {
					type = "snippets",
					-- again, include filetype, same reasoning as with augroup.
					key = string.format("__%s_snippets_%s", lang, file),
					refresh_notify = false,
				}, add_opts)
			)
			ls.add_snippets(
				lang,
				auto_lang_snips,
				vim.tbl_extend("keep", {
					type = "autosnippets",
					key = string.format("__%s_autosnippets_%s", lang, file),
					refresh_notify = false,
				}, add_opts)
			)
		end
	end

	ls.refresh_notify(lang)
end

--- Find all files+associated filetypes in a package.
---@param root string, directory of the package (immediate parent of the
--- package.json)
---@param filter function that filters filetypes, generate from in/exclude-list
--- via loader_util.ft_filter.
---@return table, string -> string[] (ft -> files).
--- Paths are normalized.
local function package_files(root, filter)
	local package = Path.join(root, "package.json")
	local data = Path.read_file(package)
	local package_data = json_decode(data)
	if
		not (
			package_data
			and package_data.contributes
			and package_data.contributes.snippets
		)
	then
		-- root doesn't contain a package.json, return no snippets.
		return {}
	end

	-- stores ft -> files(string[]).
	local ft_files = {}

	for _, snippet_entry in pairs(package_data.contributes.snippets) do
		local langs = snippet_entry.language

		if type(langs) ~= "table" then
			langs = { langs }
		end
		for _, ft in ipairs(langs) do
			if filter(ft) then
				if not ft_files[ft] then
					ft_files[ft] = {}
				end
				table.insert(ft_files[ft], Path.normalize(Path.join(root, snippet_entry.path)))
			end
		end
	end

	return ft_files
end

local function get_snippet_rtp()
	return vim.tbl_map(function(itm)
		return vim.fn.fnamemodify(itm, ":h")
	end, vim.api.nvim_get_runtime_file("package.json", true))
end

-- sanitizes opts and returns ft -> files-map for `opts` (respects in/exclude).
local function get_snippet_files(opts)
	local paths
	-- list of paths to crawl for loading (could be a table or a comma-separated-list)
	if not opts.paths then
		paths = get_snippet_rtp()
	elseif type(opts.paths) == "string" then
		paths = vim.split(opts.paths, ",")
	else
		paths = opts.paths
	end
	paths = vim.tbl_map(Path.expand, paths) -- Expand before deduping, fake paths will become nil
	paths = util.deduplicate(paths) -- Remove doppelgänger paths and ditch nil ones

	local ft_paths = {}

	local ft_filter = loader_util.ft_filter(opts.exclude, opts.include)
	for _, root_path in ipairs(paths) do
		loader_util.extend_ft_paths(
			ft_paths,
			package_files(root_path, ft_filter)
		)
	end

	return ft_paths
end

local M = {}
function M.load(opts)
	opts = opts or {}

	local ft_files = get_snippet_files(opts)
	local add_opts = loader_util.add_opts(opts)

	loader_util.extend_ft_paths(cache.ft_paths, ft_files)

	for ft, files in pairs(ft_files) do
		load_snippet_files(ft, files, add_opts)
	end
end

function M._load_lazy_loaded_ft(ft)
	for _, load_call_paths in ipairs(cache.lazy_load_paths) do
		load_snippet_files(
			ft,
			load_call_paths[ft] or {},
			load_call_paths.add_opts
		)
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

	local ft_files = get_snippet_files(opts)
	local add_opts = loader_util.add_opts(opts)

	loader_util.extend_ft_paths(cache.ft_paths, ft_files)

	-- immediately load filetypes that have already been loaded.
	-- They will not be loaded otherwise.
	for ft, files in pairs(ft_files) do
		if cache.lazy_loaded_ft[ft] then
			-- instantly load snippets if they were already loaded...
			load_snippet_files(ft, files, add_opts)

			-- don't load these files again.
			ft_files[ft] = nil
		end
	end

	ft_files.add_opts = add_opts
	table.insert(cache.lazy_load_paths, ft_files)

	-- load for current buffer on startup.
	M._load_lazy_loaded(vim.api.nvim_get_current_buf())
end

function M.edit_snippet_files()
	loader_util.edit_snippet_files(cache.ft_paths)
end

-- Make sure filename is normalized.
function M.reload_file(filename)
	local cached_data = cache.path_snippets[filename]
	if not cached_data then
		-- file is not loaded by this loader.
		return
	end

	cache.path_snippets[filename] = nil
	local add_opts = cached_data.add_opts

	-- reload file for all filetypes it occurs in.
	for ft, _ in pairs(cached_data.fts) do
		load_snippet_files(ft, { filename }, add_opts)

		ls.clean_invalidated({ inv_limit = 100 })
	end
end

return M
