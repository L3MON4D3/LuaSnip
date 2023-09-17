local ls = require("luasnip")
local package_cache = require("luasnip.loaders._caches").vscode_packages
local standalone_cache = require("luasnip.loaders._caches").vscode_standalone
local util = require("luasnip.util.util")
local loader_util = require("luasnip.loaders.util")
local Path = require("luasnip.util.path")
local log = require("luasnip.util.log").new("vscode-loader")

local json_decoders = {
	json = util.json_decode,
	jsonc = require("luasnip.util.jsonc").decode,
	["code-snippets"] = require("luasnip.util.jsonc").decode,
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

-- return all snippets in `file`.
local function get_file_snippets(file)
	local sp = require("luasnip.nodes.snippetProxy")
	local session = require("luasnip.session")
	local source = require("luasnip.session.snippet_collection.source")
	local multisnippet = require("luasnip.nodes.multiSnippet")

	-- since most snippets we load don't have a scope-field, we just insert this here by default.
	local snippets = {}

	local snippet_set_data = read_json(file)
	if snippet_set_data == nil then
		log.error("Reading json from file `%s` failed, skipping it.", file)
		return {}
	end

	for name, parts in pairs(snippet_set_data) do
		local body = type(parts.body) == "string" and parts.body
			or table.concat(parts.body, "\n")

		local ls_conf = parts.luasnip or {}

		-- we may generate multiple interfaces to the same snippet
		-- (different filetype, different triggers)

		-- context common to all snippets generated here.
		local common_context = {
			name = name,
			desc = parts.description or name,
			wordTrig = ls_conf.wordTrig,
			priority = ls_conf.priority,
			snippetType = ls_conf.autotrigger and "autosnippet" or "snippet",
		}

		-- Sometimes it's a list of prefixes instead of a single one
		local prefixes = type(parts.prefix) == "table" and parts.prefix
			or { parts.prefix }

		-- vscode documents `,`, but `.` also works.
		-- an entry `false` in this list will cause a `ft=nil` for the snippet.
		local filetypes = parts.scope and vim.split(parts.scope, "[.,]")
			or { false }

		local contexts = {}
		for _, prefix in ipairs(prefixes) do
			for _, filetype in ipairs(filetypes) do
				table.insert(
					contexts,
					{ filetype = filetype or nil, trig = prefix }
				)
			end
		end

		local snip
		if #contexts > 1 then
			-- only construct multisnippet if it is actually necessary.
			contexts.common = common_context
			snip = multisnippet._raw_ms(contexts, sp(nil, body), {})
		elseif #contexts == 1 then
			-- have to add options from common context to the trig/filetype-context.
			snip = sp(vim.tbl_extend("keep", contexts[1], common_context), body)
		end

		if snip then
			if session.config.loaders_store_source then
				-- only know file, not line or line_end.
				snip._source = source.from_location(file)
			end

			table.insert(snippets, snip)
		end
	end

	return snippets
end

-- `refresh` to optionally delay refresh_notify.
-- (it has to be called by the caller, for filetype!)
-- opts may contain:
-- `refresh_notify`: refresh snippets for filetype immediately, default false.
-- `force_reload`: don't use cache when reloading, default false
local function load_snippet_file(file, filetype, add_opts, opts)
	local duplicate = require("luasnip.nodes.duplicate")

	opts = opts or {}
	local refresh_notify =
		util.ternary(opts.refresh_notify ~= nil, opts.refresh_notify, false)
	local force_reload =
		util.ternary(opts.force_reload ~= nil, opts.force_reload, false)

	if not Path.exists(file) then
		log.error(
			"Trying to read snippets from file %s, but it does not exist.",
			file
		)
		return
	end

	local file_snippets
	local cache = package_cache.path_snippets[file]
	if cache.snippets and not force_reload then
		file_snippets = vim.tbl_map(duplicate.duplicate_addable, cache.snippets)
	else
		file_snippets = get_file_snippets(file)

		-- store snippets as-is (eg. don't copy), they will be copied when read
		-- from.
		package_cache.path_snippets[file].snippets = file_snippets
	end

	ls.add_snippets(
		filetype,
		-- only load snippets matching the language set in `package.json`.
		file_snippets,
		vim.tbl_extend("keep", {
			-- include filetype, a file may contribute snippets to multiple
			-- filetypes, and we don't want to remove snippets for ft1 when
			-- adding those for ft2.
			key = string.format("__%s_snippets_%s", filetype, file),
			refresh_notify = refresh_notify,
		}, add_opts)
	)
	log.info("Adding %s snippets from %s", #file_snippets, file)
end

--- Find all files+associated filetypes in a package.
---@param root string, directory of the package (immediate parent of the
--- package.json)
---@param filter function that filters filetypes, generate from in/exclude-list
--- via loader_util.ft_filter.
---@return table: string -> string[] (ft -> files)
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

-- sanitizes opts and returns
-- * ft -> files-map for `opts` (respects in/exclude).
-- * files -> ft-map (need to look up which filetypes a file contributes).
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

-- initializes ft_paths for `file`, and stores the add_opts for the filetype-file combination.
-- We can't just store add_opts for a single file, since via in/exclude, they
-- may differ for a single file which contributes multiple snippet-filetypes.
local function update_cache(cache, file, filetype, add_opts)
	local filecache = cache.path_snippets[file]
	if not filecache then
		filecache = {
			filetype_add_opts = {},
			filetypes = {},
		}
		cache.path_snippets[file] = filecache
	end

	filecache.filetype_add_opts[filetype] = add_opts
	filecache.filetypes[filetype] = true
end

local M = {}
function M.load(opts)
	opts = opts or {}

	-- applies in/exclude.
	local ft_files = get_snippet_files(opts)
	local add_opts = loader_util.add_opts(opts)

	loader_util.extend_ft_paths(package_cache.ft_paths, ft_files)

	log.info("Loading snippet:", vim.inspect(ft_files))
	for ft, files in pairs(ft_files) do
		for _, file in ipairs(files) do
			update_cache(package_cache, file, ft, add_opts)

			-- `false`: don't refresh while adding.
			load_snippet_file(file, ft, add_opts, { refresh_notify = false })
		end
		ls.refresh_notify(ft)
	end
end

function M._load_lazy_loaded_ft(ft)
	for _, file in ipairs(package_cache.lazy_load_paths[ft] or {}) do
		load_snippet_file(
			file,
			ft,
			package_cache.path_snippets[file].filetype_add_opts[ft],
			{ refresh_notify = false }
		)
	end
	ls.refresh_notify(ft)
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

	-- get two maps, one mapping filetype->associated files, and another
	-- mapping files->default-filetypes.
	local ft_files = get_snippet_files(opts)
	local add_opts = loader_util.add_opts(opts)

	loader_util.extend_ft_paths(package_cache.ft_paths, ft_files)

	-- immediately load filetypes that have already been loaded.
	-- They will not be loaded otherwise.
	for ft, files in pairs(ft_files) do
		-- first register add_opts for all files, then iterate over files again
		-- if they are already loaded.

		for _, file in ipairs(files) do
			update_cache(package_cache, file, ft, add_opts)
		end

		if package_cache.lazy_loaded_ft[ft] then
			for _, file in ipairs(files) do
				-- instantly load snippets if they were already loaded...
				load_snippet_file(
					file,
					ft,
					add_opts,
					{ refresh_notify = false }
				)
				log.info(
					"Immediately loading lazy-load-snippets for already-active filetype %s from files:\n%s",
					ft,
					vim.inspect(files)
				)
			end
			ls.refresh_notify(ft)

			-- don't load these files again.
			-- clearing while iterating is fine: https://www.lua.org/manual/5.1/manual.html#pdf-next
			ft_files[ft] = nil
		end
	end
	log.info("Registering lazy-load-snippets:\n%s", vim.inspect(ft_files))

	loader_util.extend_ft_paths(package_cache.lazy_load_paths, ft_files)

	-- load for current buffer on startup.
	M._load_lazy_loaded(vim.api.nvim_get_current_buf())
end

function M.edit_snippet_files()
	loader_util.edit_snippet_files(package_cache.ft_paths)
end

local function standalone_add(path, add_opts)
	local file_snippets = get_file_snippets(path)

	ls.add_snippets(
		-- nil: provided snippets are a table mapping filetype->snippets.
		"all",
		file_snippets,
		vim.tbl_extend("keep", {
			key = string.format("__snippets_%s", path),
		}, add_opts)
	)
end

function M.load_standalone(opts)
	opts = opts or {}
	local path = Path.expand(opts.path)
	local add_opts = loader_util.add_opts(opts)

	-- register file for `all`-filetype in cache.
	if not standalone_cache.ft_paths.all then
		standalone_cache.ft_paths.all = {}
	end

	-- record in cache, so edit_snippet_files can find it.
	-- Store under "all" for now, alternative: collect all filetypes the
	-- snippets contribute to.
	-- Since .code-snippets are mainly (?) project-local, that behaviour does
	-- not seem to bad.
	table.insert(standalone_cache.ft_paths.all, path)

	-- only store add_opts, we don't need to remember filetypes and the like,
	-- and here the filename is enough to identify add_opts.
	standalone_cache.path_snippets[path] = add_opts

	standalone_add(path, add_opts)
end

-- filename is normalized
function M._reload_file(filename)
	local package_cached_data = package_cache.path_snippets[filename]
	if package_cached_data then
		log.info("Re-loading snippets contributed by %s", filename)

		-- reload file for all filetypes it occurs in.
		-- only the first call actually needs to force-reload, all other can
		-- just use its snippets.
		local force_reload = true
		for ft, _ in pairs(package_cached_data.filetypes) do
			load_snippet_file(
				filename,
				ft,
				package_cached_data.filetype_add_opts[ft],
				{ force_reload = force_reload }
			)
			-- only force-reload once, then reuse updated snippets.
			force_reload = false
		end

		ls.clean_invalidated({ inv_limit = 100 })
	end

	local standalone_cached_data = standalone_cache.path_snippets[filename]
	if standalone_cached_data then
		log.info("Re-loading snippets contributed by %s", filename)
		local add_opts = standalone_cached_data

		standalone_add(filename, add_opts)
		ls.clean_invalidated({ inv_limit = 100 })
	end
end

return M
