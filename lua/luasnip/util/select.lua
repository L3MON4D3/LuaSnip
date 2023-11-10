local M = {}

local SELECT_RAW = "LUASNIP_SELECT_RAW"
local SELECT_DEDENT = "LUASNIP_SELECT_DEDENT"
local TM_SELECT = "LUASNIP_TM_SELECT"

function M.retrieve()
	local ok, val = pcall(vim.api.nvim_buf_get_var, 0, SELECT_RAW)
	if ok then
		local result = {
			val,
			vim.api.nvim_buf_get_var(0, SELECT_DEDENT),
			vim.api.nvim_buf_get_var(0, TM_SELECT),
		}

		vim.api.nvim_buf_del_var(0, SELECT_RAW)
		vim.api.nvim_buf_del_var(0, SELECT_DEDENT)
		vim.api.nvim_buf_del_var(0, TM_SELECT)

		return unpack(result)
	end
	return {}, {}, {}
end

local function get_min_indent(lines)
	-- "^(%s*)%S": match only lines that actually contain text.
	local min_indent = lines[1]:match("^(%s*)%S")
	for i = 2, #lines do
		-- %s* -> at least matches
		local line_indent = lines[i]:match("^(%s*)%S")
		-- ignore if not matched.
		if line_indent then
			-- if no line until now matched, use line_indent.
			if not min_indent or #line_indent < #min_indent then
				min_indent = line_indent
			end
		end
	end
	return min_indent
end

local function store_registers(...)
	local names = { ... }
	local restore_data = {}
	for _, name in ipairs(names) do
		restore_data[name] = {
			data = vim.fn.getreg(name),
			type = vim.fn.getregtype(name),
		}
	end
	return restore_data
end

local function restore_registers(restore_data)
	for name, name_restore_data in pairs(restore_data) do
		vim.fn.setreg(name, name_restore_data.data, name_restore_data.type)
	end
end

-- subtle: `:lua` exits VISUAL, which means that the '< '>-marks will be set correctly!
-- Afterwards, we can just use <cmd>lua, which does not change the mode.
M.select_keys =
	[[:lua require("luasnip.util.select").pre_cut()<Cr>gv"zs<cmd>lua require('luasnip.util.select').post_cut("z")<Cr>]]

local saved_registers
local lines
local start_line, start_col, end_line, end_col
local mode
function M.pre_cut()
	-- store registers so we don't change any of them.
	-- "" is affected since we perform a cut (s), 1-9 also (although :h
	-- quote_number seems to state otherwise for cuts to specific registers..?).
	saved_registers =
		store_registers("", "1", "2", "3", "4", "5", "6", "7", "8", "9", "z")

	-- store data needed for de-indenting lines.
	start_line = vim.fn.line("'<") - 1
	start_col = vim.fn.col("'<")
	end_line = vim.fn.line("'>") - 1
	end_col = vim.fn.col("'>")
	-- +1: include final line.
	lines = vim.api.nvim_buf_get_lines(0, start_line, end_line + 1, true)
	mode = vim.fn.visualmode()
end

function M.post_cut(register_name)
	-- remove trailing newline.
	local chunks = vim.split(vim.fn.getreg(register_name):gsub("\n$", ""), "\n")

	-- make sure to restore the registers to the state they were before cutting.
	restore_registers(saved_registers)

	local tm_select, select_dedent = vim.deepcopy(chunks), vim.deepcopy(chunks)

	local min_indent = get_min_indent(lines) or ""
	if mode == "V" then
		tm_select[1] = tm_select[1]:gsub("^%s+", "")
		-- remove indent from all lines:
		for i = 1, #select_dedent do
			select_dedent[i] = select_dedent[i]:gsub("^" .. min_indent, "")
		end
		-- due to the trailing newline of the last line, and vim.split's
		-- behaviour, the last line of `chunks` is always empty.
		-- Keep this
	elseif mode == "v" then
		-- if selection starts inside indent, remove indent.
		if #min_indent > start_col then
			select_dedent[1] = lines[1]:gsub(min_indent, "")
		end
		for i = 2, #select_dedent - 1 do
			select_dedent[i] = select_dedent[i]:gsub(min_indent, "")
		end

		-- remove as much indent from the last line as possible.
		if #min_indent > end_col then
			select_dedent[#select_dedent] = ""
		else
			select_dedent[#select_dedent] =
				select_dedent[#select_dedent]:gsub("^" .. min_indent, "")
		end
	else
		-- in block: if indent is in block, remove the part of it that is inside
		-- it for select_dedent.
		if #min_indent > start_col then
			local indent_in_block = min_indent:sub(start_col, #min_indent)
			for i, line in ipairs(chunks) do
				select_dedent[i] = line:gsub("^" .. indent_in_block, "")
			end
		end
	end

	vim.api.nvim_buf_set_var(0, SELECT_RAW, chunks)
	vim.api.nvim_buf_set_var(0, SELECT_DEDENT, select_dedent)
	vim.api.nvim_buf_set_var(0, TM_SELECT, tm_select)

	lines = nil
	start_line, start_col, end_line, end_col = nil, nil, nil, nil
	mode = nil
end

return M
