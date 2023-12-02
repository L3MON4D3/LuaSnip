local loader_util = require("luasnip.loaders.util")
local util = require("luasnip.util.util")
local tbl_util = require("luasnip.util.table")
local Path = require("luasnip.util.path")
local autotable = require("luasnip.util.auto_table").autotable
local digraph = require("luasnip.util.directed_graph")
local tree_watcher = require("luasnip.loaders.fs_watchers").tree
local Data = require("luasnip.loaders.data")
local session = require("luasnip.session")
local snippetcache = require("luasnip.loaders.snippet_cache")
local refresh_notify =
	require("luasnip.session.enqueueable_operations").refresh_notify
local clean_invalidated =
	require("luasnip.session.enqueueable_operations").clean_invalidated

local log = require("luasnip.util.log").new("snipmate-loader")

--- Load data from any snippet-file.
--- @param filename string
--- @return LuaSnip.Loaders.SnippetFileData
local function load_snipmate(filename)
	local buffer_ok, buffer = pcall(Path.read_file, filename)
	if not buffer_ok then
		log.error(("Could not read file %s: %s"):format(filename, buffer))
		-- return dummy-data.
		return {
			snippets = {},
			autosnippets = {},
			misc = {},
		}
	end

	local sp = require("luasnip.nodes.snippetProxy")
	local snipmate_parse_fn = require("luasnip.util.parser").parse_snipmate
	local source = require("luasnip.session.snippet_collection.source")

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

		local snip_begin_line = i
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
		local snip = sp(
			{
				trig = prefix,
				desc = description,
				wordTrig = true,
				priority = snipmate_opts.priority,
			},
			body,
			{
				parse_fn = snipmate_parse_fn,
			}
		)
		if session.config.loaders_store_source then
			snip._source = source.from_location(
				filename,
				{ line = snip_begin_line, line_end = i - 1 }
			)
		end
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
			vim.list_extend(extends, vim.split(vim.trim(line:sub(8)), "[,%s]+"))
			i = i + 1
		elseif vim.startswith(line, "#") or line:find("^%s*$") then
			-- comment and blank line
			i = i + 1
		elseif vim.startswith(line, "priority") then
			snipmate_opts.priority = tonumber(line:match("priority%s+(%d+)"))
			i = i + 1
		else
			log.error("Invalid line in %s: %s", filename, i)
			error(("Invalid line in %s: %s"):format(filename, i))
		end
	end

	return {
		snippets = snippets.snippet,
		autosnippets = snippets.autosnippet,
		misc = extends,
	}
end

-- cache snippets without filetype-association for reuse.
Data.snipmate_cache = snippetcache.new(load_snipmate)

--- Collection watches all files that belong to a collection of snippets below
--- some root, and registers new files.
local Collection = {}
local Collection_mt = {
	__index = Collection,
}

local function snipmate_package_file_filter(fname)
	return fname:match("%.snippets$")
end

function Collection.new(
	root,
	lazy,
	include_ft,
	exclude_ft,
	add_opts,
	lazy_watcher,
	fs_event_providers
)
	local ft_filter = loader_util.ft_filter(include_ft, exclude_ft)
	local o = setmetatable({
		root = root,

		--- @alias LuaSnip.Loaders.Snipmate.FileCategory
		--- | '"collection"' File only belongs to the collection
		--- | '"load"' File should be loaded

		--- Determine whether a file should be loaded, belongs to the
		--- collection, or doesn't.
		--- This distinction is important because we need to know about all
		--- files to correctly resolve `extend <someft>`, but only want to load
		--- the filetypes allowed by in/exclude.
		--- @param path string
		---@return LuaSnip.Loaders.Snipmate.FileCategory?
		categorize_file = function(path)
			if not path:sub(1, #root) == root then
				log.warn(
					"Tried to filter file `%s`, which is not inside the root `%s`.",
					path,
					root
				)
				return nil
			end
			if snipmate_package_file_filter(path) then
				if ft_filter(path) then
					return "load"
				end
				return "collection"
			end
			return nil
		end,

		add_opts = add_opts,
		lazy = lazy,
		-- store ft -> set of files that should be lazy-loaded.
		lazy_files = autotable(2, { warn = false }),
		-- store for each path the set of filetypes it has been loaded with.
		loaded_path_fts = autotable(2, { warn = false }),
		-- model filetype-extensions (`extends <someft>` in `ft.snippets`).
		-- Better than a flat table with t[ft] = {someft=true, somotherft=true}
		-- since transitive dependencies are easier to understand/query.
		-- There is an edge with source src to destination dst, if snippets for
		-- filetype src also contribute to filetype dst.
		-- Since we respect transitive `extends`, we can get all filetypes a
		-- snippet-file for some filetype A contributes to by querying the
		-- connected component of A (all filetype-vertices reachable from A).
		ft_extensions = digraph.new_labeled(),
		-- store all files in the collection, by their filetype.
		-- This information is necessary to handle `extends` even for files
		-- that are not actually loaded (due to in/exclude).
		collection_files_by_ft = autotable(2, { warn = false }),
		-- set if creation successful.
		watcher = nil,
	}, Collection_mt)

	-- only register files up to a depth of 2.
	local ok, err_or_watcher = pcall(tree_watcher, root, 2, {
		-- don't handle removals for now.
		new_file = function(path)
			---@as LuaSnip.Loaders.Snipmate.FileCategory
			local file_category = o.categorize_file(path)

			if file_category then
				-- know it's at least in the collection -> can register it.
				local file_ft = loader_util.collection_file_ft(o.root, path)
				o:register_file(path, file_ft)
				if file_category == "load" then
					-- actually load if allowed by in/exclude.
					o:add_file(path, file_ft)
				end
			end
		end,
		change_file = function(path)
			vim.schedule_wrap(function()
				o:reload(path)
			end)()
		end,
	}, { lazy = lazy_watcher, fs_event_providers = fs_event_providers })

	if not ok then
		error(("Could not create watcher: %s"):format(err_or_watcher))
	end

	o.watcher = err_or_watcher

	log.info("Initialized snippet-collection at `%s`", root)

	return o
end

--- Makes the file known to the collection, but does not load its snippets.
--- This is important because `extends` may require loading a file excluded by
--- `file_filter`, ie `include` and `exclude`.
--- @param path string
--- @param ft string
function Collection:register_file(path, ft)
	self.collection_files_by_ft[ft][path] = true
end

--- Register a file-filetype-association with the collection.
--- @param path string Path to a file that belongs to this collection.
--- @param add_ft string The original filetype this file should be added as.
---                      Since we have to support filetype-extensions, this may
---                      add the snippets of the file to several other
---                      filetypes.
function Collection:add_file(path, add_ft)
	-- register known file.
	Data.snipmate_ft_paths[add_ft][path] = true

	if self.lazy then
		if not session.loaded_fts[add_ft] then
			log.info(
				"Registering lazy-load-snippets for ft `%s` from file `%s`",
				add_ft,
				path
			)

			-- only register to load later.
			self.lazy_files[add_ft][path] = true
			return
		else
			log.info(
				"Filetype `%s` is already active, loading immediately.",
				add_ft
			)
		end
	end

	-- extended filetypes will be loaded in load_file.
	self:load_file(path, add_ft, "SkipIfLoaded")
end

--- @alias LuaSnip.Loaders.Snipmate.SkipLoad
--- | '"ForceLoad"' Always load, even if it was already loaded.
--- | '"SkipIfLoaded"' Skip the load if the file has been loaded already.

-- loads the fts that extend load_ft as well.
-- skip_load_mode allows this code to both prevent unnecessary loads (which
-- could be caused if some file is added to the same filetype more than once),
-- while still handling reload (where the files has to be loaded again for
-- every filetype, even if it already is loaded (since it may have different
-- snippets))
function Collection:load_file(path, ft, skip_load_mode)
	if skip_load_mode == "SkipIfLoaded" and self.loaded_path_fts[path][ft] then
		return
	end

	log.info("Adding snippets for filetype `%s` from file `%s`", ft, path)

	-- Set here to skip loads triggered for the same path-file-combination in
	-- subsequent code, which would trigger and endless loop.
	self.loaded_path_fts[path][ft] = true

	-- this may already be set, but setting again here ensures that a file is
	-- certainly associated with each filetype it's loaded for. (for example,
	-- file-ft-combinations loaded as a dependency from another file may not be
	-- set already).
	Data.snipmate_ft_paths[ft][path] = true

	-- snippets may already be loaded -> get them from cache.
	local data = Data.snipmate_cache:fetch(path)
	local snippets = data.snippets
	local autosnippets = data.autosnippets
	-- data.misc is user-input, clean it here.
	local extended_fts = util.deduplicate(data.misc)

	-- ignored if it already exists.
	self.ft_extensions:set_vertex(ft)
	-- make sure we don't retain any old dependencies.
	self.ft_extensions:clear_edges(path)

	for _, extended_ft in pairs(extended_fts) do
		-- ignored if it already exists.
		self.ft_extensions:set_vertex(extended_ft)
		-- snippets for extended_ft should also be loaded if ft is loaded
		-- label edge with path, so all edges from this file can be updated on
		-- reload.
		self.ft_extensions:set_edge(extended_ft, ft, path)
	end

	loader_util.add_file_snippets(
		ft,
		path,
		snippets,
		autosnippets,
		self.add_opts
	)

	-- get all filetypes this one extends (directly or transitively), and load
	-- their files.
	local load_fts = self.ft_extensions:connected_component(ft, "Backward")
	for _, extended_ft in ipairs(load_fts) do
		for file, _ in pairs(self.collection_files_by_ft[extended_ft]) do
			for _, file_ft in
				ipairs(
					self.ft_extensions:connected_component(
						extended_ft,
						"Forward"
					)
				)
			do
				-- skips load if the file is already loaded for the given filetype.
				-- One bad side-effect of this current implementation is that
				-- the edges in the graph will be reset/set multiple times,
				-- until they are retained in the last load_file-call to the
				-- last filetype.
				self:load_file(file, file_ft, "SkipIfLoaded")
			end
		end
	end

	refresh_notify(ft)
end

function Collection:do_lazy_load(lazy_ft)
	for file, _ in pairs(self.lazy_files[lazy_ft]) do
		for _, ft in
			ipairs(self.ft_extensions:connected_component(lazy_ft, "Forward"))
		do
			-- skips load if the file is already loaded for the given filetype.
			self:load_file(file, ft, "SkipIfLoaded")
		end
	end
end
-- will only do something, if the file at `path` is actually in the collection.
function Collection:reload(path)
	local loaded_fts = tbl_util.set_to_list(self.loaded_path_fts[path])
	for _, loaded_ft in ipairs(loaded_fts) do
		-- will override previously-loaded snippets from this path.
		self:load_file(path, loaded_ft, "ForceLoad")
	end

	-- clean snippets if enough were removed.
	clean_invalidated()
end

function Collection:stop()
	self.watcher:stop()
end

local M = {}

function M._load_lazy_loaded_ft(ft)
	log.info("Loading lazy-load-snippets for filetype `%s`", ft)

	for _, collection in ipairs(Data.snipmate_collections) do
		collection:do_lazy_load(ft)
	end
end

--- Generalized loading of collections.
--- @param lazy boolean Whether the collection should be loaded lazily.
--- @param opts LuaSnip.Loaders.LoadOpts?
local function _load(lazy, opts)
	local o = loader_util.normalize_opts(opts)

	local collection_roots = loader_util.resolve_root_paths(o.paths, "snippets")
	local lazy_roots = loader_util.resolve_lazy_root_paths(o.lazy_paths)

	log.info(
		"Found roots `%s` for paths `%s`.",
		vim.inspect(collection_roots),
		vim.inspect(o.paths)
	)
	if o.paths and #o.paths ~= #collection_roots then
		log.warn(
			"Could not resolve all collection-roots for paths `%s`: only found `%s`",
			vim.inspect(o.paths),
			vim.inspect(collection_roots)
		)
	end

	log.info(
		"Determined roots `%s` for lazy_paths `%s`.",
		vim.inspect(lazy_roots),
		vim.inspect(o.lazy_paths)
	)
	if o.lazy_paths and #o.lazy_paths ~= #lazy_roots then
		log.warn(
			"Could not resolve all collection-roots for lazy_paths `%s`: only found `%s`",
			vim.inspect(o.lazy_paths),
			vim.inspect(lazy_roots)
		)
	end

	for paths_lazy, roots in pairs({
		[true] = lazy_roots,
		[false] = collection_roots,
	}) do
		for _, collection_root in ipairs(roots) do
			local ok, coll_or_err = pcall(
				Collection.new,
				collection_root,
				lazy,
				o.include,
				o.exclude,
				o.add_opts,
				paths_lazy,
				o.fs_event_providers
			)

			if not ok then
				log.error(
					"Could not create collection at %s: %s",
					collection_root,
					coll_or_err
				)
			else
				table.insert(Data.snipmate_collections, coll_or_err)
			end
		end
	end
end

--- Load snipmate-snippet-collections immediately.
--- @param opts LuaSnip.Loaders.LoadOpts?
function M.load(opts)
	_load(false, opts)
end

--- Load snipmate-snippet-collections on demand.
--- @param opts LuaSnip.Loaders.LoadOpts?
function M.lazy_load(opts)
	_load(true, opts)
	-- load for current buffer on startup.
	for _, ft in
		ipairs(loader_util.get_load_fts(vim.api.nvim_get_current_buf()))
	do
		M._load_lazy_loaded_ft(ft)
	end
end

function M.clean()
	for _, collection in ipairs(Data.snipmate_collections) do
		collection:stop()
	end
	Data.snipmate_ft_paths = autotable(2)
	-- don't reset cache, snippets are correctly updated on file-change anyway,
	-- and there is no persistent data passed on.
end

return M
