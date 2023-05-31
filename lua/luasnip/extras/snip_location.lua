local Source = require("luasnip.session.snippet_collection.source")
local util = require("luasnip.util.util")

-- stylua: ignore
local tsquery_parse =
	(vim.treesitter.query and vim.treesitter.query.parse)
	and vim.treesitter.query.parse
	or vim.treesitter.parse_query

local M = {}

-- return: 4-tuple, {start_line, start_col, end_line, end_col}, range of
-- function-call.
local function lua_find_function_call_node_at(bufnr, line)
	local has_parser, parser = pcall(vim.treesitter.get_parser, bufnr, "lua")
	if not has_parser then
		error("Error while getting parser: " .. parser)
	end

	local root = parser:parse()[1]:root()
	local query = tsquery_parse("lua", [[(function_call) @f_call]])
	for _, node, _ in query:iter_captures(root, bufnr, line, line + 300) do
		if node:range() == line then
			return { node:range() }
		end
	end
	error(
		"Query for `(function_call)` starting at line %s did not yield a result."
	)
end

local function range_highlight(line_start, line_end, hl_duration_ms)
	-- make sure line_end is also visible.
	vim.api.nvim_win_set_cursor(0, { line_end, 0 })
	vim.api.nvim_win_set_cursor(0, { line_start, 0 })

	if hl_duration_ms > 0 then
		local hl_buf = vim.api.nvim_get_current_buf()

		-- highlight snippet for 1000ms
		local id = vim.api.nvim_buf_set_extmark(
			hl_buf,
			ls.session.ns_id,
			line_start - 1,
			0,
			{
				-- one line below, at col 0 => entire last line is highlighted.
				end_row = line_end - 1 + 1,
				hl_group = "Visual",
			}
		)
		vim.defer_fn(function()
			vim.api.nvim_buf_del_extmark(hl_buf, ls.session.ns_id, id)
		end, hl_duration_ms)
	end
end

local function json_find_snippet_definition(bufnr, filetype, snippet_name)
	local parser_ok, parser = pcall(vim.treesitter.get_parser, bufnr, filetype)
	if not parser_ok then
		error("Error while getting parser: " .. parser)
	end

	local root = parser:parse()[1]:root()
	-- don't want to pass through whether this file is json or jsonc, just use
	-- parser-language.
	local query = tsquery_parse(
		parser:lang(),
		([[
		(pair
		  key: (string (string_content) @key (#eq? @key "%s"))
		) @snippet
	]]):format(snippet_name)
	)
	for id, node, _ in query:iter_captures(root, bufnr) do
		if
			query.captures[id] == "snippet"
			and node:parent():parent() == root
		then
			-- return first match.
			return { node:range() }
		end
	end

	error(
		("Treesitter did not find the definition for snippet `%s`"):format(
			snippet_name
		)
	)
end

local function win_edit(file)
	vim.api.nvim_command(":e " .. file)
end

function M.jump_to_snippet(snip, opts)
	opts = opts or {}
	local hl_duration_ms = opts.hl_duration_ms or 1500
	local edit_fn = opts.edit_fn or win_edit

	local source = Source.get(snip)
	if not source then
		print("Snippet does not have a source.")
		return
	end

	edit_fn(source.file)
	-- assumption: after this, file is the current buffer.

	if source.line and source.line_end then
		-- happy path: we know both begin and end of snippet-definition.
		range_highlight(source.line, source.line_end, hl_duration_ms)
		return
	end

	local fcall_range
	local ft = util.ternary(
		vim.bo[0].filetype ~= "",
		vim.bo[0].filetype,
		vim.api.nvim_buf_get_name(0):match("%.([^%.]+)$")
	)
	if ft == "lua" then
		if source.line then
			-- in lua-file, can get region of definition via treesitter.
			-- 0: current buffer.
			local ok
			ok, fcall_range =
				pcall(lua_find_function_call_node_at, 0, source.line - 1)
			if not ok then
				print(
					"Could not determine range for snippet-definition: "
						.. fcall_range
				)
				vim.api.nvim_win_set_cursor(0, { source.line, 0 })
				return
			end
		else
			print("Can't jump to snippet: source does not provide line.")
			return
		end
	-- matches *.json or *.jsonc.
	elseif ft == "json" or ft == "jsonc" then
		local ok
		ok, fcall_range = pcall(json_find_snippet_definition, 0, ft, snip.name)
		if not ok then
			print(
				"Could not determine range of snippet-definition: "
					.. fcall_range
			)
			return
		end
	else
		print(
			("Don't know how to highlight snippet-definitions in current buffer `%s`.%s"):format(
				vim.api.nvim_buf_get_name(0),
				source.line ~= nil and " Jumping to `source.line`" or ""
			)
		)

		if source.line ~= nil then
			vim.api.nvim_win_set_cursor(0, { source.line, 0 })
		end
		return
	end
	assert(fcall_range ~= nil, "fcall_range is not nil")

	-- 1 is line_from, 3 is line_end.
	-- +1 since range is row-0-indexed.
	range_highlight(fcall_range[1] + 1, fcall_range[3] + 1, hl_duration_ms)

	local new_source = Source.from_location(
		source.file,
		{ line = fcall_range[1] + 1, line_end = fcall_range[3] + 1 }
	)
	Source.set(snip, new_source)
end

function M.jump_to_active_snippet(opts)
	local active_node =
		require("luasnip.session").current_nodes[vim.api.nvim_get_current_buf()]
	if not active_node then
		print("No active snippet.")
		return
	end

	local snip = active_node.parent.snippet
	M.jump_to_snippet(snip, opts)
end

return M
