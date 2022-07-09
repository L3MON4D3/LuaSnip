-- Check if treesitter is available
local ok_parsers, ts_parsers = pcall(require, "nvim-treesitter.parsers")
if not ok_parsers then
	ts_parsers = nil
end

local ok_utils, ts_utils = pcall(require, "nvim-treesitter.ts_utils")
if not ok_utils then
	ts_utils = nil
end

local function from_cursor_pos()
	if not ts_parsers or not ts_utils then
		return {}
	end

	local parser = ts_parsers.get_parser()
	local current_node = ts_utils.get_node_at_cursor()

	if current_node then
		return { parser:language_for_range({ current_node:range() }):lang() }
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
