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
		vim.api.nvim_feedkeys(
			vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
			"n",
			true
		)
		util.normal_move_on_insert(util.get_ext_position_begin(self.mark.id))
	end

	util.node_event(self, events.enter, no_move)
end

function TextNode:put_initial(pos)
	util.put(self:get_static_text(), pos)
end

return {
	T = T,
}
