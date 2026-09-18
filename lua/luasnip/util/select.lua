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

local function dedent_selection(chunks, selection)
	local dedented = {}
	for i, line in ipairs(chunks) do
		if selection.mode == "v" then
			-- Only the first chunk can start partway through a source line.
			local offset = i == 1 and selection.first_byte or 0
			dedented[i] = line:sub(math.max(#selection.indent - offset, 0) + 1)
		else
			dedented[i] = line:gsub("^" .. selection.indent, "")
		end
	end
	return dedented
end

local function store_registers(yank_register)
	-- Cutting can affect the unnamed and numbered registers as well as the
	-- named register used to capture the selection.
	local names =
		{ "", "1", "2", "3", "4", "5", "6", "7", "8", "9", yank_register }
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

-- Leave Visual mode first so '< and '> describe the current selection.
M.cut_keys =
	[[<Esc><cmd>lua require("luasnip.util.select").pre_yank("z")<Cr>gv"zs<cmd>lua require('luasnip.util.select').post_yank("z")<Cr>]]

-- State shared by the two halves of the selection mapping.
local pending_yank
function M.pre_yank(yank_register)
	local start_pos, end_pos = vim.fn.getpos("'<"), vim.fn.getpos("'>")
	local lines =
		vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], true)
	local mode = vim.fn.visualmode()
	local min_indent = get_min_indent(lines) or ""
	local selection = { mode = mode, indent = min_indent }
	if mode == "v" then
		selection.first_byte = start_pos[3] - 1
	elseif mode == "\22" then
		local start_col = math.min(start_pos[3], end_pos[3])
		-- Preserve the original byte-based prefix matching for blocks.
		selection.indent = #min_indent > start_col and min_indent:sub(start_col)
			or ""
	end
	pending_yank = {
		registers = store_registers(yank_register),
		selection = selection,
	}
end

function M.post_yank(yank_register)
	local yank = pending_yank
	pending_yank = nil
	-- remove trailing newline.
	local chunks = vim.split(vim.fn.getreg(yank_register):gsub("\n$", ""), "\n")

	-- make sure to restore the registers to the state they were before cutting.
	restore_registers(yank.registers)

	local selection = yank.selection
	local select_dedent = dedent_selection(chunks, selection)
	local tm_select = vim.list_extend({}, chunks)
	if selection.mode == "V" then
		-- VSCode removes all leading whitespace from the first selected line.
		tm_select[1] = tm_select[1]:gsub("^%s+", "")
	end

	vim.api.nvim_buf_set_var(0, SELECT_RAW, chunks)
	vim.api.nvim_buf_set_var(0, SELECT_DEDENT, select_dedent)
	vim.api.nvim_buf_set_var(0, TM_SELECT, tm_select)
end

return M
