local available = require("luasnip").available

local function snip_info(snippet)
	return {
		name = snippet.name,
		trigger = snippet.trigger,
		description = snippet.description,
		wordTrig = snippet.wordTrig and true or false,
		regTrig = snippet.regTrig and true or false,
		docstring = snippet:get_docstring(),
	}
end

local function get_name(buf)
	return "LuaSnip://Snippets"
end

local win_opts = { foldmethod = "indent" }
local buf_opts = { filetype = "lua" }

local function set_win_opts(win, opts)
	for opt, val in pairs(opts) do
		vim.api.nvim_win_set_option(win, opt, val)
	end
end

local function set_buf_opts(buf, opts)
	for opt, val in pairs(opts) do
		vim.api.nvim_buf_set_option(buf, opt, val)
	end
end

local function make_scratch_buf(buf)
	local opts = {
		buftype = "nofile",
		bufhidden = "wipe",
		buflisted = false,
		swapfile = false,
		modified = false,
		modeline = false,
	}

	set_buf_opts(buf, opts)
end

local function display_split(opts)
	opts = opts or {}
	opts.win_opts = opts.win_opts or win_opts
	opts.buf_opts = opts.buf_opts or buf_opts
	opts.get_name = opts.get_name or get_name

	return function(printer_result)
		-- create and open buffer on right vertical split
		vim.cmd("botright vnew")

		-- get buf and win handle
		local buf = vim.api.nvim_get_current_buf()
		local win = vim.api.nvim_get_current_win()

		-- make scratch buffer
		vim.api.nvim_buf_set_name(buf, opts.get_name(buf))
		make_scratch_buf(buf)

		-- disable diagnostics
		vim.diagnostic.disable(buf)

		-- set any extra win and buf opts
		set_win_opts(win, opts.win_opts)
		set_buf_opts(buf, opts.buf_opts)

		-- dump snippets
		local replacement = vim.split(printer_result, "\n")
		vim.api.nvim_buf_set_lines(buf, 0, 0, false, replacement)

		-- make it unmodifiable at this point
		vim.api.nvim_buf_set_option(buf, "modifiable", false)
	end
end

local function open(opts)
	opts = opts or {}
	opts.snip_info = opts.snip_info or snip_info
	opts.printer = opts.printer or vim.inspect
	opts.display = opts.display or display_split()

	-- load snippets before changing windows/buffers
	local snippets = available(opts.snip_info)

	-- open snippets
	opts.display(opts.printer(snippets))
end

return {
	open = open,
	options = { display = display_split },
}
