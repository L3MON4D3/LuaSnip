local ls = require("luasnip")
local package_cache = require("luasnip.loaders._caches").vscode_packages
local standalone_cache = require("luasnip.loaders._caches").vscode_standalone
local util = require("luasnip.util.util")
local loader_util = require("luasnip.loaders.util")
local Path = require("luasnip.util.path")
local sp = require("luasnip.nodes.snippetProxy")
local log = require("luasnip.util.log").new("vscode-loader")
local session = require("luasnip.session")
local source = require("luasnip.session.snippet_collection.source")

local json_decoders = {
	json = util.json_decode,
	jsonc = require("luasnip.util.jsonc").decode,
	["code-snippets"] = require("luasnip.util.jsonc").decode
}

local function read_json(fname)
	local data_ok, data = pcall(Path.read_file, fname)
	if not data_ok then
		log.error("Could not read file %s", fname)
		return nil
	end

	local fname_extension = Path.extension(fname)
	if json_decoders[fname_extension] == nil then
		log.error(
			"`%s` was expected to have file-extension either `json`, `jsonc` or `code-snippets`, but doesn't.",
			fname
		)
		return nil
	end
	local fname_decoder = json_decoders[fname_extension]

	local status, result = pcall(fname_decoder, data)
	if status then
		return result
	else
		log.error("Could not parse file %s: %s", fname, result)
		return nil
	end
end

-- return table mapping ft -> snippets (which is immediately compatible with what ls.add_snippets(nil, snippets) expects.)
-- default_filetype will be used for snippets without a `scope`-field.
-- set opts.ignore_scope to add all snippets to default_filetype, regardless of scope.
local function get_file_snippets(file, default_filetype, opts)
	opts = opts or {}
	local ignore_scope = util.ternary(opts.ignore_scope, opts.ignore_scope, false)

	-- since most snippets we load don't have a scope-field, we just insert this here by default.
	local snippets_by_ft = {[default_filetype] = {}}

	local snippet_set_data = read_json(file)
	if snippet_set_data == nil then
		log.error("Reading json from file `%s` failed, skipping it.", file)
		return snippets_by_ft
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
					wordTrig = ls_conf.wordTrig,
					priority = ls_conf.priority,
					snippetType = ls_conf.autotrigger and "autosnippet" or "snippet"
				}, body)

				if session.config.loaders_store_source then
					-- only know file, not line or line_end.
					snip._source = source.from_location(file)
				end

				-- snippet can be provided to multiple filetypes via scope.
				local ft_tables = {}

				-- https://code.visualstudio.com/docs/editor/userdefinedsnippets#_language-snippet-scope
				-- scope can have multiple components.
				if parts.scope and not ignore_scope then
					for _, scope in ipairs(vim.split(parts.scope, ",", { plain = true })) do
						snippets_by_ft[scope] = snippets_by_ft[scope] or {}
						table.insert(ft_tables, snippets_by_ft[scope])
					end
				else
					table.insert(ft_tables, snippets_by_ft[default_filetype])
				end

				for _, t in ipairs(ft_tables) do
					table.insert(t, snip)
				end
			end
		end)
	end

	return snippets_by_ft
end

local function load_snippet_files(lang, files, add_opts)
	for _, file in ipairs(files) do
		if Path.exists(file) then
			local file_lang_snippets

			local cached_path = package_cache.path_snippets[file]
			if cached_path then
				file_lang_snippets = vim.deepcopy(cached_path.snippets)
				cached_path.fts[lang] = true
			else
				-- get all snippets from file, regardless of scope.
				file_lang_snippets = get_file_snippets(file, lang, {ignore_scope = true})[lang]
				-- store snippets to prevent parsing the same file more than once.
				package_cache.path_snippets[file] = {
					snippets = vim.deepcopy(file_lang_snippets),
					add_opts = add_opts,
					fts = { [lang] = true },
				}
			end

			ls.add_snippets(
				lang,
				-- only load snippets matching the language set in `package.json`.
				file_lang_snippets,
				vim.tbl_extend("keep", {
					-- again, include filetype, same reasoning as with augroup.
					key = string.format("__%s_package_snippets_%s", lang, file),
					refresh_notify = false,
				}, add_opts)
			)
			log.info(
				"Adding %s snippets for filetype `%s` from %s",
				#file_lang_snippets,
				lang,
				file
			)
		else
			log.error(
				"Trying to read snippets from file %s, but it does not exist.",
				lang,
				file
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
	-- if root doesn't contain a package.json, or it contributes no snippets,
	-- return no snippets.
	if not Path.exists(package) then
		log.warn(
			"Looked for `package.json` in `root`, does not exist.",
			package
		)
		return {}
	end

	local package_data = read_json(package)
	if not package_data then
		-- since it is a `.json`, the json not being correct should be an error.
		log.error("Could not read json from `%s`", package)
		return {}
	end

	if
		not package_data.contributes or not package_data.contributes.snippets
	then
		log.warn(
			"Package %s does not contribute any snippets, skipping it",
			package
		)
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
				local normalized_snippet_file =
					Path.normalize(Path.join(root, snippet_entry.path))

				-- the file might not exist..
				if normalized_snippet_file then
					table.insert(ft_files[ft], normalized_snippet_file)
				else
					log.warn(
						"Could not find file %s from advertised in %s",
						snippet_entry.path,
						root
					)
				end
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
	paths = vim.tbl_filter(function(v)
		return v
	end, paths) -- ditch nil
	paths = util.deduplicate(paths) -- Remove doppelgänger paths

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

	loader_util.extend_ft_paths(package_cache.ft_paths, ft_files)

	log.info("Loading snippet:", vim.inspect(ft_files))
	for ft, files in pairs(ft_files) do
		load_snippet_files(ft, files, add_opts)
	end
end

function M._load_lazy_loaded_ft(ft)
	for _, load_call_paths in ipairs(package_cache.lazy_load_paths) do
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
		if not package_cache.lazy_loaded_ft[ft] then
			M._load_lazy_loaded_ft(ft)
			log.info("Loading lazy-load-snippets for filetype `%s`", ft)
			package_cache.lazy_loaded_ft[ft] = true
		end
	end
end

function M.lazy_load(opts)
	opts = opts or {}

	local ft_files = get_snippet_files(opts)
	local add_opts = loader_util.add_opts(opts)

	loader_util.extend_ft_paths(package_cache.ft_paths, ft_files)

	-- immediately load filetypes that have already been loaded.
	-- They will not be loaded otherwise.
	for ft, files in pairs(ft_files) do
		if package_cache.lazy_loaded_ft[ft] then
			-- instantly load snippets if they were already loaded...
			load_snippet_files(ft, files, add_opts)
			log.info(
				"Immediately loading lazy-load-snippets for already-active filetype %s from files:\n%s",
				ft,
				vim.inspect(files)
			)

			-- don't load these files again.
			ft_files[ft] = nil
		end
	end
	log.info("Registering lazy-load-snippets:\n%s", vim.inspect(ft_files))

	ft_files.add_opts = add_opts
	table.insert(package_cache.lazy_load_paths, ft_files)

	-- load for current buffer on startup.
	M._load_lazy_loaded(vim.api.nvim_get_current_buf())
end

function M.edit_snippet_files()
	loader_util.edit_snippet_files(package_cache.ft_paths)
end

local function standalone_add(path, add_opts)
	local file_snippets = get_file_snippets(path, "all")
	standalone_cache.path_snippets[path] = {
		add_opts = add_opts
	}

	ls.add_snippets(
		-- nil: provided snippets are a table mapping filetype->snippets.
		nil,
		file_snippets,
		vim.tbl_extend("keep", {
			key = string.format("__standalone_snippets_%s", path),
		}, add_opts)
	)
end

function M.load_standalone(opts)
	opts = opts or {}
	local add_opts = loader_util.add_opts(opts)
	local path = opts.path

	standalone_add(path, add_opts)
end

-- Make sure filename is normalized.
function M._reload_file(filename)
	local package_cached_data = package_cache.path_snippets[filename]
	if package_cached_data then
		log.info("Re-loading snippets contributed by %s", filename)

		package_cache.path_snippets[filename] = nil
		local add_opts = package_cached_data.add_opts

		-- reload file for all filetypes it occurs in.
		for ft, _ in pairs(package_cached_data.fts) do
			load_snippet_files(ft, { filename }, add_opts)

		end
		ls.clean_invalidated({ inv_limit = 100 })
	end
	local standalone_cached_data = standalone_cache.path_snippets[filename]
	if standalone_cached_data then
		log.info("Re-loading snippets contributed by %s", filename)

		standalone_cache.path_snippets[filename] = nil
		local add_opts = standalone_cached_data.add_opts

		standalone_add(filename, add_opts)
		ls.clean_invalidated({ inv_limit = 100 })
	end
end

return M
