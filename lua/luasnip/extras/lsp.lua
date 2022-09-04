local luasnip_ns_id = require("luasnip.session").ns_id
local ls = require("luasnip")

local M = {}

---Apply text/snippetTextEdits (at most one snippetText though).
---@param snippet_or_text_edits `(snippetTextEdit|textEdit)[]`
--- snippetTextEdit as defined in https://github.com/rust-lang/rust-analyzer/blob/master/docs/dev/lsp-extensions.md#snippet-textedit)
---@param bufnr number, buffer where the snippet should be expanded.
---@param offset_encoding string|nil, 'utf-8,16,32' or ni
---@param apply_text_edits_fn function, has to apply regular textEdits, most
--- likely `vim.lsp.util.apply_text_edits` (we expect its' interface).
function M.apply_text_edits(snippet_or_text_edits, bufnr, offset_encoding, apply_text_edits_fn)
	-- plain textEdits, applied using via `apply_text_edits_fn`.
	local text_edits = {}
	-- contains keys
	--  - snippet (parsed snippet)
	--  - mark (extmark, textrange replaced by the snippet)
	local snippet_params

	for _, v in ipairs(snippet_or_text_edits) do
		if v.newText and v.insertTextFormat == 2 then
			assert(snippet_params == nil, "Only one snippetTextEdit may be applied at once.")

			-- from vim.lsp.apply_text_edits.
			local start_row = v.range.start.line
			local start_col = vim.lsp.util._get_line_byte_from_position(bufnr, v.range.start, offset_encoding)
			local end_row = v.range['end'].line
			local end_col = vim.lsp.util._get_line_byte_from_position(bufnr, v.range['end'], offset_encoding)

			snippet_params = {
				snippet_body = v.newText,
				mark = vim.api.nvim_buf_set_extmark(bufnr, luasnip_ns_id, start_row, start_col, {
					end_row = end_row,
					end_col = end_col
				}),
			}
		else
			table.insert(text_edits, v)
		end
	end

	-- first apply regular textEdits...
	apply_text_edits_fn(text_edits, bufnr, offset_encoding)

	-- ...then the snippet.
	local mark_info = vim.api.nvim_buf_get_extmark_by_id(bufnr, luasnip_ns_id, snippet_params.mark, {details = true})
	local mark_begin_pos = {mark_info[1], mark_info[2]}
	local mark_end_pos = {mark_info[3].end_row, mark_info[3].end_col}

	-- luasnip can only expand snippets in the active buffer, so switch (nop if
	-- buf already active).
	vim.api.nvim_set_current_buf(bufnr)
	ls.lsp_expand(snippet_params.snippet_body, {
		pos = mark_begin_pos,
		clear_region = {
			from = mark_begin_pos,
			to = mark_end_pos,
		},
	})
end

function M.update_capabilities(capabilities)
	if not capabilities.experimental then
		capabilities.experimental = {}
	end
	capabilities.experimental.snippetTextEdit = true

	return capabilities
end

return M
