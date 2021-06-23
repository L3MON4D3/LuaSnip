local node_mod = require("luasnip.nodes.node")
local util = require("luasnip.util.util")

local TextNode = node_mod.Node:new()

local function T(static_text)
	return TextNode:new({ static_text = static_text, markers = {}, type = 0 })
end

-- Don't touch gravities for TextNodes.
function TextNode:set_mark_rgrav(_, _) end

function TextNode:input_enter()
	vim.api.nvim_feedkeys(
		vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
		"n",
		true
	)
	util.normal_move_on_mark_insert(self.markers[1])
end

function TextNode:put_initial(pos)
	util.put(self:get_static_text(), pos)
end

return {
	T = T,
}
