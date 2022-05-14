local Cache = require("luasnip.loaders._caches")
local util = require("luasnip.util.util")

local M = {}

local function default_format(path, _)
	path = path:gsub(
		vim.fn.stdpath("data") .. "/site/pack/packer/start",
		"$PLUGINS"
	)
	if vim.env.HOME then
		path = path:gsub(vim.env.HOME .. "/.config/nvim", "$CONFIG")
	end
	return path
end

--- Quickly jump to snippet-file from any source for the active filetypes.
---@param opts table, options for this function:
--- - format: fn(path:string, source_name:string) -> string|nil
---   source_name is one of "vscode", "snipmate" or "lua".
---   May be used to format the displayed items. For example, replace the
---   excessively long packer-path with something shorter.
---   If format returns nil for some item, the item will not be displayed.
function M.edit_snippet_files(opts)
	opts = opts or {}
	local format = opts.format or default_format

	local fts = util.get_snippet_filetypes()
	vim.ui.select(fts, {
		prompt = "Select filetype:",
	}, function(ft, _)
		if ft then
			local ft_paths = {}
			local items = {}

			-- concat files from all loaders for the selected filetype ft.
			for _, cache_name in ipairs({ "vscode", "snipmate", "lua" }) do
				for _, path in ipairs(Cache[cache_name].ft_paths[ft] or {}) do
					local fmt_name = format(path, cache_name)
					if fmt_name then
						table.insert(ft_paths, path)
						table.insert(items, fmt_name)
					end
				end
			end

			-- prompt user again if there are multiple files providing this filetype.
			if #ft_paths > 1 then
				vim.ui.select(items, {
					prompt = "Multiple files for this filetype, choose one:",
				}, function(_, indx)
					if indx and ft_paths[indx] then
						vim.cmd("edit " .. ft_paths[indx])
					end
				end)
			elseif ft_paths[1] then
				vim.cmd("edit " .. ft_paths[1])
			end
		end
	end)
end

function M.cleanup()
	Cache.cleanup()

	-- remove reload-autocommands.
	vim.cmd([[
		augroup luasnip_watch_reload
		autocmd!
		augroup END
	]])
end

return M
