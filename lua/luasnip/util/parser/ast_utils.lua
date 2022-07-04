local M = {}

local types = require("luasnip.util.parser.neovim_ast").node_type
local Node_mt = getmetatable(
	require("luasnip.util.parser.neovim_parser").parse("$0")
)

--- Find type of 0-placeholder/choice/tabstop, if it exists.
--- Ignores transformations.
---@param ast table: ast
---@return number, number: first, the type of the node with position 0, then
--- the child of `ast` containing it.
local function zero_node(ast)
	-- find placeholder/tabstop/choice with position 0, but ignore those that
	-- just apply transformations, this should return the node where the cursor
	-- ends up on exit.
	-- (this node should also exist in this snippet, as long as it was formatted
	-- correctly).
	if ast.tabstop == 0 and not ast.transform then
		return ast
	end
	for indx, child in ipairs(ast.children or {}) do
		local zn, _ = zero_node(child)
		if zn then
			return zn, indx
		end
	end

	-- no 0-node in this ast.
	return nil, nil
end

local function max_position(ast)
	local max = ast.tabstop or -1

	for _, child in ipairs(ast.children or {}) do
		local mp = max_position(child)
		if mp > max then
			max = mp
		end
	end

	return max
end

local function replace_position(ast, p1, p2)
	if ast.tabstop == p1 then
		ast.tabstop = p2
	end
	for _, child in ipairs(ast.children or {}) do
		replace_position(child, p1, p2)
	end
end

function M.fix_zero(ast)
	local zn, ast_child_with_0_indx = zero_node(ast)
	-- if zn exists, is a tabstop and an immediate child of `ast`, the snippet can
	-- be accurately represented by luasnip (also if zn does not exist, ofc).
	-- Otherwise the ast needs to be modified as described below.
	if
		not zn
		or (
			zn
			and zn.type == types.TABSTOP
			and ast.children[ast_child_with_0_indx] == zn
		)
	then
		return
	end

	-- bad, a choice or placeholder is at position 0.
	-- replace all ${0:...} with ${n+1:...} (n highest position)
	-- max_position is at least 0, all's good.
	local max_pos = max_position(ast)
	replace_position(ast, 0, max_pos + 1)

	-- insert $0 as a direct child to snippet.
	table.insert(
		ast.children,
		ast_child_with_0_indx + 1,
		setmetatable({
			type = types.TABSTOP,
			tabstop = 0,
		}, Node_mt)
	)
end

M.types = types
M.Node_mt = Node_mt
return M
