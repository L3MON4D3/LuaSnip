local util = require("luasnip.util.util")
local types = require("luasnip.util.types")
local conf = require("luasnip.config")

local function subsnip_init_children(node, parent, children, position_so_far)
	node.absolute_position = vim.deepcopy(position_so_far)
	local pos_depth = #position_so_far + 1

	for indx, child in ipairs(children) do
		if child.type == types.snippetNode then
			child.ext_opts = util.increase_ext_prio(
				vim.deepcopy(parent.ext_opts),
				conf.config.ext_prio_increase
			)
			child.snippet = parent.snippet
		end

		position_so_far[pos_depth] = indx
		child:subsnip_init(position_so_far)

		-- as position_so_far is passed by reference, it might be deeper now.
		-- nil entries for keys greater than the current depth.
		for i = pos_depth+1, #position_so_far do
			position_so_far[i] = nil
		end
	end
end

return {
	subsnip_init_children = subsnip_init_children
}
