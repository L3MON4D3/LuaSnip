local util = require("luasnip.util.util")
local loader_util = require("luasnip.loaders.util")
local Path = require("luasnip.util.path")
local log = require("luasnip.util.log").new("vscode-loader")
local autotable = require("luasnip.util.auto_table").autotable
local path_watcher = require("luasnip.loaders.fs_watchers").path
local Data = require("luasnip.loaders.data")
local session = require("luasnip.session")
local refresh_notify =
	require("luasnip.session.enqueueable_operations").refresh_notify
local clean_invalidated =
	require("luasnip.session.enqueueable_operations").clean_invalidated

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

--- Load snippets from vscode-snippet-file.
--- @param file string Path to file
---@return LuaSnip.Loaders.SnippetFileData
local function get_file_snippets(file)
	local sp = require("luasnip.nodes.snippetProxy")
	local source = require("luasnip.session.snippet_collection.source")
	local multisnippet = require("luasnip.nodes.multiSnippet")

	-- since most snippets we load don't have a scope-field, we just insert
	-- them here by default.
	local snippets = {}

	local snippet_set_data = read_json(file)
	if snippet_set_data == nil then
		log.error("Reading json from file `%s` failed, skipping it.", file)

		return {
			snippets = {},
			autosnippets = {},
			misc = {},
		}
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

	return {
		snippets = snippets,
		autosnippets = {},
		misc = {},
	}
end

-- has to be set in separate module to allow different module-path-separators
-- in `require`.
Data.vscode_cache =
	require("luasnip.loaders.snippet_cache").new(get_file_snippets)

--- Parse package.json(c), determine all files that contribute snippets, and
--- which filetype is associated with them.
--- @param manifest string
--- @return table<string, table<string, true|nil>>
local function get_snippet_files(manifest)
	-- if root doesn't contain a package.json, or it contributes no snippets,
	-- return no snippets.
	if not Path.exists(manifest) then
		log.warn("Manifest %s does not exist", manifest)
		return {}
	end

	local package_data = read_json(manifest)
	if not package_data then
		-- since it is a `.json/jsonc`, the json not being correct should be an error.
		log.error("Could not read json from `%s`", manifest)
		return {}
	end

	if
		not package_data.contributes or not package_data.contributes.snippets
	then
		log.warn("Manifest %s does not contribute any snippets.", manifest)
		return {}
	end

	-- stores ft -> files -> true|nil, allow iterating files and their
	-- filetypes while preventing duplicates.
	local ft_file_set = autotable(2, { warn = false })

	-- parent-directory of package.json(c), all files in the package.json(c)
	-- are relative to it.
	local package_parent = Path.parent(manifest)

	for _, snippet_entry in pairs(package_data.contributes.snippets) do
		local absolute_path = Path.join(package_parent, snippet_entry.path)

		local normalized_snippet_file = Path.normalize(absolute_path)

		if not normalized_snippet_file then
			-- path does not exist (yet), try and guess the correct path anyway.
			normalized_snippet_file = Path.normalize_nonexisting(absolute_path)
			log.warn(
				"Could not find file %s advertised in %s, guessing %s as the absolute and normalized path.",
				absolute_path,
				manifest,
				normalized_snippet_file
			)
		end

		local langs = snippet_entry.language
		if type(langs) ~= "table" then
			langs = { langs }
		end
		for _, ft in ipairs(langs) do
			ft_file_set[ft][normalized_snippet_file] = true
		end
	end

	return ft_file_set
end

-- Responsible for watching a single json-snippet-file.
local SnippetfileWatcher = {}
local SnippetfileWatcher_mt = { __index = SnippetfileWatcher }

function SnippetfileWatcher.new(
	path,
	initial_ft,
	fs_event_providers,
	lazy,
	load_cb
)
	local o = setmetatable({
		path = path,
		load_cb = load_cb,
		-- track which filetypes this file has been loaded for, so we can
		-- reload for all of them.
		loaded_fts = { [initial_ft] = true },
	}, SnippetfileWatcher_mt)

	local load_all_fts = function()
		for ft, _ in pairs(o.loaded_fts) do
			load_cb(path, ft)
			refresh_notify(ft)
		end
	end
	local ok, err_or_watcher = pcall(path_watcher, path, {
		add = load_all_fts,
		change = function()
			load_all_fts()

			-- clean snippets if enough were removed.
			clean_invalidated()
		end,
	}, { lazy = lazy, fs_event_providers = fs_event_providers })

	if not ok then
		-- has to be handled by caller, we can't really proceed if the creation
		-- failed.
		error(
			("Could not create path_watcher for path %s: %s"):format(
				path,
				err_or_watcher
			)
		)
	end

	o.watcher = err_or_watcher

	return o
end

-- called by collection.
function SnippetfileWatcher:add_ft(ft)
	if self.loaded_fts[ft] then
		-- already loaded.
		return
	end
	self.loaded_fts[ft] = true
	self.load_cb(self.path, ft)
end

function SnippetfileWatcher:stop()
	self.watcher:stop()
end

--- Collection watches all files that belong to a collection of snippets below
--- some root, and registers new files.
local Collection = {}
local Collection_mt = {
	__index = Collection,
}

function Collection.new(
	manifest_path,
	lazy,
	include_ft,
	exclude_ft,
	add_opts,
	lazy_watcher,
	fs_event_providers
)
	local ft_filter = loader_util.ft_filter(include_ft, exclude_ft)
	local o = setmetatable({
		lazy = lazy,
		-- store ft -> set of files that should be lazy-loaded.
		lazy_files = autotable(2, { warn = false }),
		fs_event_providers = fs_event_providers,

		-- store path-watchers (so we don't register more than one for one
		-- path), and so we can disable them.
		path_watchers = {},
		-- for really loading a file.
		-- this is not done in Collection:load itself, since it may have to be
		-- performed as a callback on file-creation.
		load_callback = function(path, ft)
			local data = Data.vscode_cache:fetch(path)
			-- autosnippets are included in snippets for this loader.
			local snippets = data.snippets
			loader_util.add_file_snippets(ft, path, snippets, {}, add_opts)
		end,
		-- initialized in a bit, we have to store+reset a watcher for the manifest-file.
		manifest_watcher = nil,
	}, Collection_mt)

	-- callback for updating the file-filetype-associations from the manifest.
	local update_manifest = function()
		local manifest_ft_paths = get_snippet_files(manifest_path)
		for ft, path_set in pairs(manifest_ft_paths) do
			if ft_filter(ft) then
				for path, _ in pairs(path_set) do
					o:add_file(path, ft)
				end
			end
		end
	end

	local watcher_ok, err = pcall(path_watcher, manifest_path, {
		-- don't handle removals for now.
		add = update_manifest,
		change = update_manifest,
	}, { lazy = lazy_watcher, fs_event_providers = fs_event_providers })

	if not watcher_ok then
		error(("Could not create watcher: %s"):format(err))
	end
	o.manifest_watcher = watcher_ok

	log.info("Initialized snippet-collection with manifest %s", manifest_path)

	return o
end

-- Add file with some filetype to collection, load according to lazy_load.
function Collection:add_file(path, ft)
	Data.vscode_ft_paths[ft][path] = true

	if self.lazy then
		if not session.loaded_fts[ft] then
			log.info(
				"Registering lazy-load-snippets for ft `%s` from file `%s`",
				ft,
				path
			)

			-- only register to load later.
			self.lazy_files[ft][path] = true
			return
		else
			log.info(
				"Filetype `%s` is already active, loading immediately.",
				ft
			)
		end
	end

	self:load_file(path, ft)
end

function Collection:load_file(path, ft)
	log.info("Registering file %s with filetype %s for loading.", path, ft)
	if not self.path_watchers[path] then
		-- always register these lazily, that way an upate to the package.json
		-- without the snippet-file existing will work!
		-- Also make sure we use the same fs_event_providers.
		local ok, watcher_or_err = pcall(
			SnippetfileWatcher.new,
			path,
			ft,
			self.fs_event_providers,
			true,
			self.load_callback
		)
		if not ok then
			log.error(
				"Could not create SnippetFileWatcher for path %s: %s",
				path,
				watcher_or_err
			)
			return
		end
		self.path_watchers[path] = watcher_or_err
	else
		-- make new filetype known to existing watcher.
		self.path_watchers[path]:add_ft(ft)
	end
end

-- stop all watchers associated with this collection, to make sure no snippets
-- are added from this collection again.
function Collection:stop()
	self.manifest_watcher:stop()
	for _, watcher in pairs(self.path_watchers) do
		watcher:stop()
	end
end

function Collection:do_lazy_load(ft)
	for file, _ in pairs(self.lazy_files[ft]) do
		self:load_file(file, ft)
	end
end

local M = {}

local function get_rtp_paths()
	return vim.list_extend(
		-- would be very surprised if this yields duplicates :D
		vim.api.nvim_get_runtime_file("package.json", true),
		vim.api.nvim_get_runtime_file("package.jsonc", true)
	)
end

--- Generate list of manifest-paths from list of directory-paths.
--- If nil, search rtp.
--- If a given directory, or the mani
---
--- @param paths string|table? List of existing directories. If nil, search runtimepath.
---@return string[] manifest_paths
local function get_manifests(paths)
	local manifest_paths = {}
	-- list of paths to crawl for loading (could be a table or a comma-separated-list)
	if paths then
		-- Get path to package.json/package.jsonc, or continue if it does not exist.
		for _, dir in ipairs(paths) do
			local tentative_manifest_path =
				Path.expand(Path.join(dir, "package.json"))
			-- expand returns nil for paths that don't exist.
			if tentative_manifest_path then
				table.insert(manifest_paths, tentative_manifest_path)
			else
				tentative_manifest_path =
					Path.expand(Path.join(dir, "package.jsonc"))
				if tentative_manifest_path then
					table.insert(manifest_paths, tentative_manifest_path)
				else
					log.warn(
						"Could not find package.json(c) in path %s (expanded to %s).",
						dir,
						Path.expand(dir)
					)
				end
			end
		end
	else
		manifest_paths = get_rtp_paths()
	end

	return manifest_paths
end

--- Generate list of paths to manifests that may not yet exist, from list of
--- directories (which also may not yet exist).
--- One peculiarity: This will generate two paths for each directory, since we
--- don't know if the package.json or the package.jsonc will be created.
--- This may cause a bit of overhead (not much due to snippet-cache) if both
--- are created and contribute the same snippets, but that's unlikely and/or
--- user error :P
--- @param paths string[]
---@return string[]
local function get_lazy_manifests(paths)
	local lazy_manifest_paths = {}
	if paths then
		-- list of directories, convert to list of existing manifest-files.
		if type(paths) == "string" then
			paths = vim.split(paths, ",")
		end
		for _, dir in ipairs(paths) do
			local absolute_dir = Path.expand_maybe_nonexisting(dir)

			table.insert(
				lazy_manifest_paths,
				Path.join(absolute_dir, "package.json")
			)
			table.insert(
				lazy_manifest_paths,
				Path.join(absolute_dir, "package.jsonc")
			)
		end
	end

	return lazy_manifest_paths
end

local function _load(lazy, opts)
	local o = loader_util.normalize_opts(opts)

	local manifests = get_manifests(o.paths)
	local lazy_manifests = get_lazy_manifests(o.lazy_paths)

	log.info(
		"Found manifests `%s` for paths `%s`.",
		vim.inspect(manifests),
		vim.inspect(o.paths)
	)
	if o.paths and #o.paths ~= #manifests then
		log.warn(
			"Could not resolve all manifests for paths `%s`: only found `%s`",
			vim.inspect(o.paths),
			vim.inspect(manifests)
		)
	end

	log.info(
		"Determined roots `%s` for lazy_paths `%s`.",
		vim.inspect(lazy_manifests),
		vim.inspect(o.lazy_paths)
	)
	-- two lazy manifests from each lazy directory.
	if o.lazy_paths and #o.lazy_paths ~= 2 * #lazy_manifests then
		log.warn(
			"Could not resolve all manifests for lazy_paths `%s`: only found `%s`",
			vim.inspect(o.lazy_paths),
			vim.inspect(lazy_manifests)
		)
	end

	for is_lazy, manifest_paths in pairs({
		[true] = lazy_manifests,
		[false] = manifests,
	}) do
		for _, manifest_path in ipairs(manifest_paths) do
			local ok, coll_or_err = pcall(
				Collection.new,
				manifest_path,
				lazy,
				o.include,
				o.exclude,
				o.add_opts,
				is_lazy,
				o.fs_event_providers
			)

			if not ok then
				log.error(
					"Could not create collection for manifest %s: %s",
					manifest_path,
					coll_or_err
				)
			else
				table.insert(Data.vscode_package_collections, coll_or_err)
			end
		end
	end
end

function M._load_lazy_loaded_ft(ft)
	log.info("Loading lazy-load-snippets for filetype `%s`", ft)

	for _, collection in ipairs(Data.vscode_package_collections) do
		collection:do_lazy_load(ft)
	end
	-- no need to lazy_load standalone-snippets.
end

function M.load(opts)
	_load(false, opts)
end

function M.lazy_load(opts)
	_load(true, opts)

	-- load for current buffer on startup.
	for _, ft in
		ipairs(loader_util.get_load_fts(vim.api.nvim_get_current_buf()))
	do
		M._load_lazy_loaded_ft(ft)
	end
end

function M.load_standalone(opts)
	opts = opts or {}

	local lazy = vim.F.if_nil(opts.lazy, false)
	local add_opts = loader_util.make_add_opts(opts)
	local fs_event_providers =
		vim.F.if_nil(opts.fs_event_providers, { autocmd = true, libuv = false })

	local path
	if not lazy then
		path = Path.expand(opts.path)
		if not path then
			log.error(
				"Expanding path %s does not produce an existing path.",
				opts.path
			)
			return
		end
	else
		path = Path.expand_maybe_nonexisting(opts.path)
	end

	Data.vscode_ft_paths["all"][path] = true

	local ok, watcher_or_err = pcall(
		SnippetfileWatcher.new,
		path,
		"all",
		fs_event_providers,
		lazy,
		function()
			local data = Data.vscode_cache:fetch(path)
			-- autosnippets are included in snippets for this loader.
			local snippets = data.snippets
			loader_util.add_file_snippets("all", path, snippets, {}, add_opts)
		end
	)

	if not ok then
		log.error(
			"Could not create SnippetFileWatcher for path %s: %s",
			path,
			watcher_or_err
		)
		return
	end

	table.insert(Data.vscode_standalone_watchers, watcher_or_err)
end

function M.clean()
	for _, collection in ipairs(Data.vscode_package_collections) do
		collection:stop()
	end
	Data.vscode_package_collections = {}
	for _, standalone_watcher in ipairs(Data.vscode_standalone_watchers) do
		standalone_watcher:stop()
	end
	Data.vscode_standalone_watchers = {}

	Data.vscode_ft_paths = autotable(2)
	-- don't reset cache, there's no reason to discard the already-loaded
	-- snippets as long as they're unchanged.
end

return M
