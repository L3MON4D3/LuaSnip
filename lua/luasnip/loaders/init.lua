local util = require("luasnip.util.util")
local Path = require("luasnip.util.path")
local loader_util = require("luasnip.loaders.util")
local session = require("luasnip.session")
local loader_data = require("luasnip.loaders.data")
local fs_watchers = require("luasnip.loaders.fs_watchers")
local log = require("luasnip.util.log").new("loader")

local M = {}

-- used to map cache-name to name passed to format.
local clean_name = {
	vscode_packages = "vscode",
	vscode_standalone = "vscode-standalone",
	snipmate = "snipmate",
	lua = "lua",
}
local function default_format(path, _)
	path = path:gsub(
		vim.pesc(vim.fn.stdpath("data") .. "/site/pack/packer/start"),
		"$PLUGINS"
	)
	if vim.env.HOME then
		path = path:gsub(vim.pesc(vim.env.HOME .. "/.config/nvim"), "$CONFIG")
	end
	return path
end

local function default_edit(file)
	vim.cmd("edit " .. file)
end

--- Quickly jump to snippet-file from any source for the active filetypes.
---@param opts nil|table, options for this function:
--- - ft_filter: fn(filetype:string) -> bool
---   Optionally filter filetypes which can be picked from. `true` -> filetype
---   is listed, `false` -> not listed.
---
--- - format: fn(path:string, source_name:string) -> string|nil
---   source_name is one of "vscode", "snipmate" or "lua".
---   May be used to format the displayed items. For example, replace the
---   excessively long packer-path with something shorter.
---   If format returns nil for some item, the item will not be displayed.
---
--- - edit: fn(file:string): this function is called with the snippet-file as
---   the lone argument.
---   The default is a function which just calls `vim.cmd("edit " .. file)`.
function M.edit_snippet_files(opts)
	opts = opts or {}
	local format = opts.format or default_format
	local edit = opts.edit or default_edit
	local extend = opts.extend or function(_, _)
		return {}
	end

	local function ft_edit_picker(ft, _)
		if ft then
			local ft_paths = {}
			local items = {}

			-- concat files from all loaders for the selected filetype ft.
			for cache_name, ft_file_set in pairs({
				vscode_packages = loader_data.vscode_ft_paths[ft],
				vscode_standalone = {},
				snipmate = loader_data.snipmate_ft_paths[ft],
				lua = loader_data.lua_ft_paths[ft],
			}) do
				for path, _ in pairs(ft_file_set or {}) do
					local fmt_name = format(path, clean_name[cache_name])
					if fmt_name then
						table.insert(ft_paths, path)
						table.insert(items, fmt_name)
					end
				end
			end

			-- extend filetypes with user-defined function.
			local extended = extend(ft, ft_paths)
			assert(
				type(extended) == "table",
				"You must return a table in extend function"
			)
			for _, pair in ipairs(extended) do
				table.insert(items, pair[1])
				table.insert(ft_paths, pair[2])
			end

			-- prompt user again if there are multiple files providing this filetype.
			if #ft_paths > 1 then
				vim.ui.select(items, {
					prompt = "Multiple files for this filetype, choose one:",
				}, function(_, indx)
					if indx and ft_paths[indx] then
						edit(ft_paths[indx])
					end
				end)
			elseif ft_paths[1] then
				edit(ft_paths[1])
			end
		end
	end

	local ft_filter = opts.ft_filter or util.yes

	local all_fts = {}
	vim.list_extend(all_fts, util.get_snippet_filetypes())
	vim.list_extend(
		all_fts,
		loader_util.get_load_fts(vim.api.nvim_get_current_buf())
	)
	all_fts = util.deduplicate(all_fts)

	local filtered_fts = {}
	for _, ft in ipairs(all_fts) do
		if ft_filter(ft) then
			table.insert(filtered_fts, ft)
		end
	end

	if #filtered_fts == 1 then
		ft_edit_picker(filtered_fts[1])
	elseif #filtered_fts > 1 then
		vim.ui.select(filtered_fts, {
			prompt = "Select filetype:",
		}, ft_edit_picker)
	end
end

function M.cleanup()
	require("luasnip.loaders.from_lua").clean()
	require("luasnip.loaders.from_snipmate").clean()
	require("luasnip.loaders.from_vscode").clean()
end

function M.load_lazy_loaded(bufnr)
	local fts = loader_util.get_load_fts(bufnr)

	for _, ft in ipairs(fts) do
		if not session.loaded_fts[ft] then
			require("luasnip.loaders.from_lua")._load_lazy_loaded_ft(ft)
			require("luasnip.loaders.from_snipmate")._load_lazy_loaded_ft(ft)
			require("luasnip.loaders.from_vscode")._load_lazy_loaded_ft(ft)
		end
		session.loaded_fts[ft] = true
	end
end

function M.reload_file(path)
	local realpath = Path.normalize(path)
	if not realpath then
		return nil, ("Could not reload file %s: does not exist."):format(path)
	else
		fs_watchers.write_notify(realpath)
		return true
	end
end

return M
