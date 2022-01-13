local node_mod = require("luasnip.nodes.node")
local util = require("luasnip.util.util")
local types = require("luasnip.util.types")
local events = require("luasnip.util.events")

local TextNode = node_mod.Node:new()

local function T(static_text)
	return TextNode:new({
		static_text = util.wrap_value(static_text) or { "" },
		mark = nil,
		type = types.textNode,
	})
end

function TextNode:input_enter(no_move)
	if not no_move then
		local mark_begin_pos = self.mark:pos_begin()
		if vim.fn.mode() == "i" then
			util.insert_move_on(mark_begin_pos)
		else
			vim.api.nvim_feedkeys(
				vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
				"n",
				true
			)
			util.normal_move_on_insert(mark_begin_pos)
		end
	end

	self:event(events.enter, no_move)
end

function TextNode:update_all_dependents() end

return {
	T = T,
}
