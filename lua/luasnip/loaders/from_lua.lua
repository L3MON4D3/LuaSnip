-- loads snippets from directory structured almost like snipmate-collection:
-- - files all named <ft>.lua
-- - each returns table containing keys (optional) "snippets" and
--   "autosnippets", value for each a list of snippets.

local cache = require("luasnip.loaders._caches").lua
local path_mod = require("luasnip.util.path")
local loader_util = require("luasnip.loaders.util")
local util = require("luasnip.util.util")
local ls = require("luasnip")

local M = {}

local function load_files(ft, files)
	for _, file in ipairs(files) do
		local func_string = path_mod.read_file(file)
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
			ft = ft,
		}

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

		ls.add_snippets(ft, file_snippets, {
			type = "snippets",
			key = "__snippets_" .. file,
			-- prevent refresh here, will be done outside loop.
			refresh_notify = false,
		})
		ls.add_snippets(ft, file_autosnippets, {
			type = "autosnippets",
			key = "__autosnippets_" .. file,
			refresh_notify = false,
		})
	end

	ls.refresh_notify(ft)
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

function M.load(opts)
	local load_paths = loader_util.get_load_paths_snipmate_like(
		opts,
		"luasnippets",
		"lua"
	)

	-- also add files from collection to cache (collection of all loaded
	-- files by filetype, useful for editing files for some filetype).
	loader_util.extend_ft_paths(cache.ft_paths, load_paths)

	for ft, files in pairs(load_paths) do
		load_files(ft, files)
	end
end

function M.lazy_load(opts)
	local load_paths = loader_util.get_load_paths_snipmate_like(
		opts,
		"luasnippets",
		"lua"
	)

	loader_util.extend_ft_paths(cache.ft_paths, load_paths)

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
	local file_cache = cache.path_snippets[filename]
	-- only clear and load(!!! snippets may not actually be loaded, lazy_load)
	-- if the snippets were really loaded.
	if file_cache then
		for _, snip in ipairs(file_cache.snippets) do
			snip:invalidate()
		end
		for _, snip in ipairs(file_cache.autosnippets) do
			snip:invalidate()
		end

		local ft = file_cache.ft

		-- only refresh all filetypes if invalidated snippets were actually cleaned.
		ls.clean_invalidated({ inv_limit = 100 })
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

-- register during startup (not really startup, as soon as this file is
-- required) so it'll work even if lazy_load is only called after the events
-- for some buffers already fired.
vim.cmd([[
augroup _luasnip_lua_lazy_load
	autocmd!
	au BufWinEnter,FileType * lua require('luasnip.loaders.from_lua')._load_lazy_loaded()
augroup END
]])

return M
