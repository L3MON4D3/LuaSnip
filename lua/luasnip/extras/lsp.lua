local luasnip_ns_id = require("luasnip.session").ns_id
local ls = require("luasnip")
local session = ls.session
local log = require("luasnip.util.log").new("lsp")
local util = require("luasnip.util.util")

local M = {}

-- copied from init.lua, maybe find some better way to get it.
local function _jump_into_default(snippet)
	local current_buf = vim.api.nvim_get_current_buf()
	if session.current_nodes[current_buf] then
		local current_node = session.current_nodes[current_buf]
		if current_node.pos > 0 then
			-- snippet is nested, notify current insertNode about expansion.
			current_node.inner_active = true
		else
			-- snippet was expanded behind a previously active one, leave the i(0)
			-- properly (and remove the snippet on error).
			local ok, err = pcall(current_node.input_leave, current_node)
			if not ok then
				log.warn("Error while leaving snippet: ", err)
				current_node.parent.snippet:remove_from_jumplist()
			end
		end
	end

	return util.no_region_check_wrap(snippet.jump_into, snippet, 1)
end

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

	-- list of snippet-parameters. These contain keys
	--  - snippet (parsed snippet)
	--  - mark (extmark, textrange replaced by the snippet)
	local all_snippet_params = {}

	for _, v in ipairs(snippet_or_text_edits) do
		if v.newText and v.insertTextFormat == 2 then
			-- from vim.lsp.apply_text_edits.
			local start_row = v.range.start.line
			local start_col = vim.lsp.util._get_line_byte_from_position(bufnr, v.range.start, offset_encoding)
			local end_row = v.range['end'].line
			local end_col = vim.lsp.util._get_line_byte_from_position(bufnr, v.range['end'], offset_encoding)

			table.insert(all_snippet_params, {
				snippet_body = v.newText,
				mark = vim.api.nvim_buf_set_extmark(bufnr, luasnip_ns_id, start_row, start_col, {
					end_row = end_row,
					end_col = end_col
				}),
			})
		else
			table.insert(text_edits, v)
		end
	end

	-- first apply regular textEdits...
	apply_text_edits_fn(text_edits, bufnr, offset_encoding)

	-- ...then the snippetTextEdits.

	-- store expanded snippets, if there are multiple we need to properly chain them together.
	local expanded_snippets = {}
	for i, snippet_params in ipairs(all_snippet_params) do
		local mark_info = vim.api.nvim_buf_get_extmark_by_id(bufnr, luasnip_ns_id, snippet_params.mark, {details = true})
		local mark_begin_pos = {mark_info[1], mark_info[2]}
		local mark_end_pos = {mark_info[3].end_row, mark_info[3].end_col}

		-- luasnip can only expand snippets in the active buffer, so switch (nop if
		-- buf already active).
		vim.api.nvim_set_current_buf(bufnr)

		-- use expand_opts to chain snippets behind each other and store the
		-- expanded snippets.
		-- With the regular expand_opts, we will immediately jump into the
		-- first snippet, if it contains an i(1), the following snippets will
		-- belong inside it, which we don't want here: we want the i(0) of a
		-- snippet to lead to the next (also skipping the i(-1)).
		-- Even worse: by default, we would jump into the snippets during
		-- snip_expand, which should only happen for the first, the later
		-- snippets should be reached by jumping through the previous ones.
		local expand_opts = {
			pos = mark_begin_pos,
			clear_region = {
				from = mark_begin_pos,
				to = mark_end_pos,
			},
		}

		if i == 1 then
			-- for first snippet: jump into it, and store the expanded snippet.
			expand_opts.jump_into_func = function(snip)
				expanded_snippets[i] = snip
				local cr = _jump_into_default(snip)
				return cr
			end
		else
			-- don't jump into the snippet, just store it.
			expand_opts.jump_into_func = function(snip)
				expanded_snippets[i] = snip

				-- let the already-active node stay active.
				return session.current_nodes[bufnr]
			end
			-- jump from previous i0 directly to start_node.
			expand_opts.jumplist_insert_func = function(_, start_node, _, _)
					start_node.prev = expanded_snippets[i-1].insert_nodes[0]
					expanded_snippets[i-1].insert_nodes[0].next = start_node

					-- skip start_node while jumping around.
					-- start_node of first snippet behaves normally!
					function start_node:jump_into(dir, no_move)
						return (dir == 1 and self.next or self.prev):jump_into(dir, no_move)
					end
			end
		end

		ls.lsp_expand(snippet_params.snippet_body, expand_opts)
	end
end

function M.update_capabilities(capabilities)
	if not capabilities.experimental then
		capabilities.experimental = {}
	end
	capabilities.experimental.snippetTextEdit = true

	return capabilities
end

return M
