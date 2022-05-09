local Cache = require("luasnip.loaders._caches")
local util = require("luasnip.util.util")

local M = {}

local function default_format(path, source_name)
	return source_name .. ": " .. path
end

--- Quickly jump to snippet-file from any source for the active filetypes.
---@param opts table, options for this function:
--- - format: fn(path, source_name) -> string.
---   May be used to format the displayed items. For example, replace the
---   excessively long packer-path with something shorter.
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
					table.insert(ft_paths, path)
					table.insert(items, format(path, cache_name))
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
			else
				vim.cmd("edit " .. ft_paths[1])
			end
		end
	end)
end

return M
