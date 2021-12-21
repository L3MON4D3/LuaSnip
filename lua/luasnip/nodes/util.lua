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
			target[i] = vim.deepcopy(parent_insert_position)
			target[i][#target[i] + 1] = arg
		else
			-- arg-position is absolute.
			-- copy because arg could be a node (whose absolute_insert_position _may_ change).
			target[i] = vim.deepcopy(arg.absolute_insert_position)
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

local function leave_nodes_between(parent, child)
	local nodes = get_nodes_between(parent, child.absolute_position)
	-- reverse order, leave child first.
	for i = #nodes, 1, -1 do
		nodes[i]:input_leave()
	end
end

local function enter_nodes_between(parent, child)
	local nodes = get_nodes_between(parent, child.absolute_position)
	for _, node in ipairs(nodes) do
		node:input_enter()
	end
end

local function select_node(node)
	vim.api.nvim_feedkeys(
		vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
		"n",
		true
	)
	-- columns in screencolumns.
	local node_begin, node_end = node.mark:pos_begin_end()
	util.normal_move_on(node_begin)
	vim.api.nvim_feedkeys(
		vim.api.nvim_replace_termcodes("v", true, false, true),
		"n",
		true
	)
	util.normal_move_before(node_end)
	vim.api.nvim_feedkeys(
		vim.api.nvim_replace_termcodes("o<C-G>", true, false, true),
		"n",
		true
	)
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
}
