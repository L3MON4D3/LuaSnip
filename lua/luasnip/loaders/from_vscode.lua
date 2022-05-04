local ls = require("luasnip")
local cache = require("luasnip.loaders._caches").vscode
local util = require("luasnip.util.util")
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

local function load_snippet_file(lang, snippet_set_path)
	if not Path.exists(snippet_set_path) then
		return
	end
	local data = Path.read_file(snippet_set_path)
	local snippet_set_data = json_decode(data)
	if snippet_set_data == nil then
		return
	end

	-- TODO: make check if file was already parsed once, we can store+reuse the
	-- snippets.

	local lang_snips = {}
	local auto_lang_snips = {}
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
				}, body)

				if ls_conf.autotrigger then
					table.insert(auto_lang_snips, snip)
				else
					table.insert(lang_snips, snip)
				end
			end
		end)
	end
	ls.add_snippets(lang, lang_snips, { type = "snippets" })
	ls.add_snippets(lang, auto_lang_snips, { type = "autosnippets" })
end

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
				table.insert(ft_files[ft], Path.join(root, snippet_entry.path))
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
	opts = opts or {}

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
	for ft, files in pairs(get_snippet_files(opts)) do
		for _, file in ipairs(files) do
			load_snippet_file(ft, file)
		end
	end
end

function M._luasnip_vscode_lazy_load()
	local fts = util.get_snippet_filetypes()
	for _, ft in ipairs(fts) do
		if not cache.lazy_loaded_ft[ft] then
			cache.lazy_loaded_ft[ft] = true
			M.load({ paths = cache.lazy_load_paths, include = { ft } })
		end
	end
end

function M.lazy_load(opts)
	opts = opts or {}

	-- We have to do this here too, because we have to store them in lozy_load_paths
	if not opts.paths then
		opts.paths = get_snippet_rtp()
	elseif type(opts.paths) == "string" then
		opts.paths = vim.split(opts.paths, ",")
	end
	vim.list_extend(cache.lazy_load_paths, opts.paths)

	cache.lazy_load_paths = util.deduplicate(cache.lazy_load_paths) -- Remove doppelgänger paths and ditch nil ones

	vim.cmd([[
    augroup _luasnip_vscode_lazy_load
        autocmd!
        au BufWinEnter,FileType * lua require('luasnip.loaders.from_vscode')._luasnip_vscode_lazy_load()
        au User LuasnipCleanup lua require('luasnip.loaders._caches').vscode:clean()
    augroup END
	]])
end

return M
