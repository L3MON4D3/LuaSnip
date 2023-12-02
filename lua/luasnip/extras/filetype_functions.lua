local function from_cursor_pos()
	-- get_parser errors if parser not present (no grammar for language).
	local has_parser, parser = pcall(vim.treesitter.get_parser)

	if has_parser then
		local cursor = require("luasnip.util.util").get_cursor_0ind()
		-- assumption: languagetree uses 0-indexed byte-ranges.
		return {
			parser
				:language_for_range({
					cursor[1],
					cursor[2],
					cursor[1],
					cursor[2],
				})
				:lang(),
		}
	else
		return {}
	end
end

local function from_filetype()
	return vim.split(vim.bo.filetype, ".", true)
end

-- NOTE: Beware that the resulting filetypes may differ from the ones in `vim.bo.filetype`. (for
-- example the filetype for LaTeX is 'latex' and not 'tex' as in `vim.bo.filetype`)  --
local function from_pos_or_filetype()
	local from_cursor = from_cursor_pos()
	if not vim.tbl_isempty(from_cursor) then
		return from_cursor
	else
		return from_filetype()
	end
end

local function from_filetype_load(bufnr)
	return vim.split(vim.api.nvim_buf_get_option(bufnr, "filetype"), ".", true)
end

local function extend_load_ft(extend_fts)
	setmetatable(extend_fts, {
		-- if the filetype is not extended, only it itself should be loaded.
		-- preventing ifs via __index.
		__index = function(t, ft)
			local val = { ft }
			rawset(t, ft, val)
			return val
		end,
	})

	for ft, _ in pairs(extend_fts) do
		-- append the regular filetype to the extend-filetypes.
		table.insert(extend_fts[ft], ft)
	end

	return function(bufnr)
		local fts =
			vim.split(vim.api.nvim_buf_get_option(bufnr, "filetype"), ".", true)
		local res = {}

		for _, ft in ipairs(fts) do
			vim.list_extend(res, extend_fts[ft])
		end

		return res
	end
end

return {
	from_filetype = from_filetype,
	from_cursor_pos = from_cursor_pos,
	from_pos_or_filetype = from_pos_or_filetype,
	from_filetype_load = from_filetype_load,
	extend_load_ft = extend_load_ft,
}
