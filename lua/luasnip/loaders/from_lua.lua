-- loads snippets from directory structured almost like snipmate-collection:
-- - files all named <ft>.lua
-- - each returns table containing keys (optional) "snippets" and
--   "autosnippets", value for each a list of snippets.

local cache = require("luasnip.loaders._caches").lua
local path_mod = require("luasnip.util.path")
local loader_util = require("luasnip.loaders.util")
local util = require("luasnip.util.util")

local M = {}

local function load_files(ft, files)
	local ft_snippets = {}
	local ft_autosnippets = {}

	for _, file in ipairs(files) do
		-- 0444 = 292, eg. open with rrr.
		local fd = vim.loop.fs_open(file, "r", 292)

		if not fd then
			error("Couldn't find file " .. file)
		end

		local size = vim.loop.fs_fstat(fd).size
		local func_string = vim.loop.fs_read(fd, size)
		-- bring snippet-constructors into global scope for that function.
		func_string = 'require("luasnip").setup_snip_env() ' .. func_string
		local file_snippets, file_autosnippets = loadstring(func_string)()

		-- make sure these aren't nil.
		file_snippets = file_snippets or {}
		file_autosnippets = file_autosnippets or {}

		-- keep track of snippet-source.
		cache.path_snippets[file] = {
			snippets = file_snippets,
			autosnippets = file_autosnippets,
		}

		vim.list_extend(ft_snippets, file_snippets)
		vim.list_extend(ft_autosnippets, file_autosnippets)

		-- use lua autocommands here as soon as they're stable.
		-- stylua: ignore
		vim.cmd(string.format(
			[[
				augroup luasnip_watch_%s
				autocmd!
				autocmd BufWritePost %s lua require("luasnip.loaders.from_lua").reload_file("%s")
			]],
			-- augroup name may not contain spaces.
			file:gsub(" ", "_"),
			-- escape for autocmd-pattern.
			file:gsub(" ", "\\ "),
			file
		))
	end

	ls.add_snippets(ft, ft_snippets, { type = "snippets" })
	ls.add_snippets(ft, ft_autosnippets, { type = "autosnippets" })
end

-- extend table like {lua = {path1}, c = {path1, path2}, ...}.
-- TODO: prevent duplicates here? should only occur if one collection is loaded
-- twice.
local function extend_ft_paths(paths, new_paths)
	for ft, path in pairs(new_paths) do
		if paths[ft] then
			table.insert(paths[ft], path)
		else
			paths[ft] = { path }
		end
	end
end

-- return table like {lua = path, c = path}.
local function get_ft_paths(root)
	local ft_paths = {}

	local files = path_mod.scandir(root)
	for _, file in ipairs(files) do
		-- true: separate filename from extension.
		local ft = path_mod.basename(file, true)
		ft_paths[ft] = file
	end

	return ft_paths
end

function M._load_lazy_loaded()
	local fts = util.get_snippet_filetypes()
	for _, ft in ipairs(fts) do
		if not cache.lazy_loaded_ft[ft] then
			cache.lazy_loaded_ft[ft] = true
			load_files(ft, cache.lazy_load_paths[ft] or {})
		end
	end
end

local function get_load_paths(opts)
	opts = opts or {}

	local load_paths = {}
	for _, collection_root in
		ipairs(loader_util.normalize_paths(opts.paths, "luasnippets"))
	do
		local collection_ft_paths = get_ft_paths(collection_root)

		extend_ft_paths(load_paths, collection_ft_paths)

		-- also add files from collection to cache (collection of all loaded
		-- files by filetype, useful for editing files for some filetype).
		extend_ft_paths(cache.ft_paths, collection_ft_paths)
	end

	-- remove files for excluded/non-included filetypes here.
	local ft_filter = loader_util.ft_filter(opts.exclude, opts.include)
	for ft, _ in pairs(load_paths) do
		if not ft_filter(ft) then
			load_paths[ft] = nil
		end
	end

	return load_paths
end

function M.load(opts)
	local load_paths = get_load_paths(opts)

	for ft, files in pairs(load_paths) do
		load_files(ft, files)
	end
end

function M.lazy_load(opts)
	local load_paths = get_load_paths(opts)

	for ft, files in pairs(load_paths) do
		if cache.lazy_loaded_ft[ft] then
			-- instantly load snippets if they were already loaded...
			load_files(ft, files)
		else
			-- and append them to the files to load for some filetype,
			-- otherwise.
			cache.lazy_load_paths[ft] = cache.lazy_load_paths[ft] or {}
			vim.list_extend(cache.lazy_load_paths[ft], files)
		end
	end

	-- call once for current filetype. Necessary for lazy_loading snippets in
	-- empty, initial buffer, and will not cause issues like duplicate
	-- snippets.
	M._load_lazy_loaded()
end

function M.reload_file(filename)
	-- only clear and load(!!! snippets may not actually be loaded, lazy_load)
	-- if the snippets were really loaded.
	if cache.path_snippets[filename] then
		for _, snip in ipairs(cache.path_snippets[filename].snippets) do
			snip:invalidate()
		end
		for _, snip in ipairs(cache.path_snippets[filename].autosnippets) do
			snip:invalidate()
		end

		ls.clean_invalidated({ inv_limit = 100 })

		local ft = path_mod.basename(filename, true)
		ls.refresh_notify(ft)

		load_files(ft, { filename })
	end
end

function M.edit_snippet_files()
	local fts = util.get_snippet_filetypes()
	vim.ui.select(fts, {
		prompt = "Select filetype:",
	}, function(item, _)
		if item then
			local ft_paths = cache.ft_paths[item]
			if ft_paths then
				-- prompt user again if there are multiple files providing this filetype.
				if #ft_paths > 1 then
					vim.ui.select(ft_paths, {
						prompt = "Multiple files for this filetype, choose one:",
					}, function(multi_item)
						vim.cmd("edit " .. multi_item)
					end)
				else
					vim.cmd("edit " .. ft_paths[1])
				end
			else
				print("No file for this filetype.")
			end
		end
	end)
end

-- register during startup so it'll work even if lazy_load is only called after
-- the events for some buffers already fired.
vim.cmd([[
augroup _luasnip_vscode_lazy_load
	autocmd!
	au BufWinEnter,FileType * lua require('luasnip.loaders.from_lua')._load_lazy_loaded()
	au User LuasnipCleanup lua require('luasnip.loaders._caches').lua:clean()
augroup END
]])

return M
