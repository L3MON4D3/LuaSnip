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
		end
		-- undo changes to position_so_far.
		position_so_far[pos_depth] = nil
	end
end

local function make_args_absolute(args, node_insert_position, target)
	for i, arg in ipairs(args) do
		if type(arg) == "number" then
			-- the arg is a number, should be interpreted relative to direct
			-- parent.
			node_insert_position[#node_insert_position] = arg
			target[i] = vim.deepcopy(node_insert_position)
		else
			-- arg-position is absolute.
			target[i] = arg.absolute_position
		end
	end
end

local function wrap_args(args)
	if type(args) ~= "table" or
	   (type(args) == "table" and args.absolute_position) then
		-- args is one single arg, wrap it.
		return {args}
	else
		return args
	end
end

local function get_nodes_between(parent, child_pos)
	local nodes = {}

	local indx = #parent.absolute_position + 1
	local prev = parent
	while child_pos[indx] do
		local next = prev:resolve_position(child_pos[indx])
		nodes[#nodes + 1] = next
		prev = next
		indx = indx + 1
	end

	return nodes
end

return {
	subsnip_init_children = subsnip_init_children,
	init_child_positions_func = init_child_positions_func,
	make_args_absolute = make_args_absolute,
	wrap_args = wrap_args,
	get_nodes_between = get_nodes_between
}
