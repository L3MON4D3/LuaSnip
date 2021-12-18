local util = require("luasnip.util.util")
local types = require("luasnip.util.types")
local conf = require("luasnip.config")

local function subsnip_init_children(parent, children)
	for _, child in ipairs(children) do
		if child.type == types.snippetNode then
			child.ext_opts = util.increase_ext_prio(
				vim.deepcopy(parent.ext_opts),
				conf.config.ext_prio_increase
			)
			child.snippet = parent.snippet
		end

		child:subsnip_init()
	end
end

local function init_child_positions_func(key, node_children_key, child_func_name)
	-- maybe via load()?
	return function(node, position_so_far)
		node[key] = vim.deepcopy(position_so_far)
		local pos_depth = #position_so_far + 1

		for indx, child in ipairs(node[node_children_key]) do
			position_so_far[pos_depth] = indx
			child[child_func_name](child, position_so_far)

			-- nil entries for set key in this loop.
			position_so_far[pos_depth] = nil
		end
		-- undo changes to position_so_far.
		position_so_far[pos_depth] = nil
	end
end

return {
	subsnip_init_children = subsnip_init_children,
	init_child_positions_func = init_child_positions_func
}
