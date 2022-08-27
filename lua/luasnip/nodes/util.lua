local util = require("luasnip.util.util")
local ext_util = require("luasnip.util.ext_opts")
local types = require("luasnip.util.types")

local function subsnip_init_children(parent, children)
	for _, child in ipairs(children) do
		if child.type == types.snippetNode then
			child.snippet = parent.snippet
			child:resolve_child_ext_opts()
		end
		child:resolve_node_ext_opts()
		child:subsnip_init()
	end
end

local function init_child_positions_func(
	key,
	node_children_key,
	child_func_name
)
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

local function make_args_absolute(args, parent_insert_position, target)
	for i, arg in ipairs(args) do
		if type(arg) == "number" then
			-- the arg is a number, should be interpreted relative to direct
			-- parent.
			local t = vim.deepcopy(parent_insert_position)
			table.insert(t, arg)
			target[i] = { absolute_insert_position = t }
		else
			-- insert node or absolute_indexer itself, node's absolute_insert_position may be nil, check for that during
			-- usage.
			target[i] = arg
		end
	end
end

local function wrap_args(args)
	-- stylua: ignore
	if type(args) ~= "table" or
	  (type(args) == "table" and args.absolute_insert_position) then
		-- args is one single arg, wrap it.
		return { args }
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

local function leave_nodes_between(parent, child, no_move)
	local nodes = get_nodes_between(parent, child.absolute_position)
	-- reverse order, leave child first.
	for i = #nodes, 1, -1 do
		nodes[i]:input_leave(no_move)
	end
end

local function enter_nodes_between(parent, child, no_move)
	local nodes = get_nodes_between(parent, child.absolute_position)
	for _, node in ipairs(nodes) do
		node:input_enter(no_move)
	end
end

local function select_node(node)
	local node_begin, node_end = node.mark:pos_begin_end_raw()
	util.any_select(node_begin, node_end)
end

local function print_dict(dict)
	print(vim.inspect(dict, {
		process = function(item, path)
			if path[#path] == "node" or path[#path] == "dependent" then
				return "node@" .. vim.inspect(item.absolute_position)
			elseif path[#path] ~= vim.inspect.METATABLE then
				return item
			end
		end,
	}))
end

local function init_node_opts(opts)
	local in_node = {}
	if not opts then
		opts = {}
	end

	-- copy once here, the opts might be reused.
	in_node.node_ext_opts =
		ext_util.complete(vim.deepcopy(opts.node_ext_opts or {}))

	if opts.merge_node_ext_opts == nil then
		in_node.merge_node_ext_opts = true
	else
		in_node.merge_node_ext_opts = opts.merge_node_ext_opts
	end

	return in_node
end

return {
	subsnip_init_children = subsnip_init_children,
	init_child_positions_func = init_child_positions_func,
	make_args_absolute = make_args_absolute,
	wrap_args = wrap_args,
	get_nodes_between = get_nodes_between,
	leave_nodes_between = leave_nodes_between,
	enter_nodes_between = enter_nodes_between,
	select_node = select_node,
	print_dict = print_dict,
	init_node_opts = init_node_opts,
}
