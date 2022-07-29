local ast_utils = require("luasnip.util.parser.ast_utils")
local Ast = require("luasnip.util.parser.neovim_ast")
local tNode = require("luasnip.nodes.textNode")
local iNode = require("luasnip.nodes.insertNode")
local fNode = require("luasnip.nodes.functionNode")
local cNode = require("luasnip.nodes.choiceNode")
local dNode = require("luasnip.nodes.dynamicNode")
local sNode = require("luasnip.nodes.snippet")
local functions = require("luasnip.util.functions")
local Environ = require("luasnip.util.environ")
local session = require("luasnip.session")
local util = require("luasnip.util.util")

local M = {}

local _split = function(s)
	return vim.split(s, "\n", { plain = true })
end

local types = ast_utils.types

local to_node

local function fix_node_indices(nodes)
	local used_nodes = {}
	for _, node in ipairs(nodes) do
		if node.pos and node.pos > 0 then
			used_nodes[node.pos] = node
		end
	end

	for _, v, i in util.key_sorted_pairs(used_nodes) do
		v.pos = i
	end
	return nodes
end

local function ast2luasnip_nodes(ast_nodes)
	local nodes = {}
	for i, ast_node in ipairs(ast_nodes) do
		nodes[i] = ast_node.parsed
	end

	return fix_node_indices(nodes)
end

local function var_func(varname, variable)
	local transform_func
	if variable.transform then
		transform_func = ast_utils.apply_transform(variable.transform)
	else
		transform_func = util.id
	end
	return function(_, parent)
		local v = parent.snippet.env[varname]
		local lines
		if type(v) == "table" then
			-- Avoid issues with empty vars
			if #v > 0 then
				lines = v
			else
				lines = { "" }
			end
		else
			lines = { v }
		end
		return transform_func(lines)
	end
end

local function copy_func(tabstop)
	local transform_func
	if tabstop.transform then
		transform_func = ast_utils.apply_transform(tabstop.transform)
	else
		transform_func = util.id
	end
	return function(args)
		return transform_func(args[1])
	end
end

---If this tabstop-node (CHOICE, TABSTOP or PLACEHOLDER) is a copy of another,
---set that up and return, otherwise return false.
---@param ast table: ast-node.
---@return boolean: whether the node is now parsed.
local function tabstop_node_copy_inst(ast)
	local existing_tabstop_ast_node = ast.copies
	if existing_tabstop_ast_node then
		-- this tabstop is a mirror of an already-parsed tabstop/placeholder.
		ast.parsed = fNode.F(copy_func(ast), { existing_tabstop_ast_node.parsed })
		return true
	end
	return false
end
-- these actually create nodes from any AST.
local to_node_funcs = {
	-- careful! this parses the snippet into a list of nodes, not a full snippet!
	-- The table can then be passed to the regular snippet-constructors.
	[types.SNIPPET] = function(ast, _)
		ast.parsed = ast2luasnip_nodes(ast.children)
	end,
	[types.TEXT] = function(ast, _)
		local text = _split(ast.esc)
		ast.parsed = tNode.T(text)
	end,
	[types.CHOICE] = function(ast)
		-- even choices may be copies.
		if tabstop_node_copy_inst(ast) then
			return
		end

		local choices = {}
		for i, choice in ipairs(ast.items) do
			choices[i] = tNode.T(_split(choice))
		end

		ast.parsed = cNode.C(ast.tabstop, choices)
	end,
	[types.TABSTOP] = function(ast)
		if tabstop_node_copy_inst(ast) then
			return
		end
		-- tabstops don't have placeholder-text.
		ast.parsed = iNode.I(ast.tabstop)
	end,
	[types.PLACEHOLDER] = function(ast, state)
		if tabstop_node_copy_inst(ast) then
			return
		end

		local node

		if #ast.children == 1 and ast.children[1].type == types.TEXT then
			-- placeholder only contains text, like `"${1:adsf}"`.
			-- `"${1}"` are parsed as tabstops.
			node = iNode.I(ast.tabstop, ast.children[1].esc)
		else
			local snip = sNode.SN(ast.tabstop, ast2luasnip_nodes(ast.children))
			if not snip:is_interactive() then
				-- this placeholder only contains text or (transformed)
				-- variables, so an insertNode can be generated from its
				-- contents on expansion.
				node = dNode.D(ast.tabstop, function(_, parent)
					-- create new snippet that only contains the parsed
					-- snippetNode.
					-- The children have to be copied to prevent every
					-- expansion getting the same object.
					local snippet = sNode.S("", snip:copy())

					-- get active env from snippet.
					snippet:fake_expand({ env = parent.snippet.env })
					local iText = snippet:get_static_text()

					-- no need to un-escape iText, that was already done.
					return sNode.SN(nil, iNode.I(1, iText))
				end, {})
			else
				node = session.config.parser_nested_assembler(ast.tabstop, snip)
			end
		end

		ast.parsed = node
	end,
	[types.VARIABLE] = function(ast, state)
		local var = ast.name
		local fn
		if state.var_functions[var] then
			fn = state.var_functions[var]
		else
			fn = var_func(var, ast)
		end

		local f = fNode.F(fn, {})

		-- if the variable is preceded by \n<indent>, the indent is applied to
		-- all lines of the variable (important for eg. TM_SELECTED_TEXT).
		if ast.previous_text ~= nil and #ast.previous_text > 1 then
			local last_line_indent = ast.previous_text[#ast.previous_text]:match(
				"^%s+$"
			)
			if last_line_indent then
				-- TM_SELECTED_TEXT contains the indent of the selected
				-- snippets, which leads to correct indentation if the
				-- snippet is expanded at the position the text was removed
				-- from.
				-- This seems pretty stupid, but TM_SELECTED_TEXT is
				-- desigend to be compatible with vscode.
				-- Use SELECT_DEDENT insted.
				-- stylua: ignore
				local indentstring = var ~= "TM_SELECTED_TEXT"
					and "$PARENT_INDENT" .. last_line_indent
					or last_line_indent

				f = sNode.ISN(nil, { f }, indentstring)
			end
		end

		ast.parsed = f
	end,
}

--- Converts any ast into luasnip-nodes.
--- Snippets return a table of nodes, those can be used like the return-value of `fmt`.
---@param ast table: AST, as generated by `require("vim.lsp._snippet").parse`
---@param state table:
--- - `var_functions`: table, maps varname to custom function for that variable.
---   For now, only used when parsing snipmate-snippets.
---@return table: node corresponding to `ast`.
function to_node(ast, state)
	if not Ast.is_node(ast) then
		-- ast is not an ast (probably a luasnip-node), return it as-is.
		return ast
	end
	return to_node_funcs[ast.type](ast, state)
end

--- Converts any ast into usable nodes.
---@param ast table: AST, as generated by `require("vim.lsp._snippet").parse`
---@param state table:
--- - `var_functions`: table, maps varname to custom function for that variable.
---   For now, only used when parsing snipmate-snippets.
---@return table: list of luasnip-nodes.
function M.to_luasnip_nodes(ast, state)
	state = state or {}
	state.var_functions = state.var_functions or {}

	-- fix disallowed $0 in snippet.
	-- TODO(logging): report changes here.
	ast_utils.fix_zero(ast)

	-- Variables need the text just in front of them to determine whether to
	-- indent all lines of the Variable.
	ast_utils.give_vars_previous_text(ast)

	local ast_nodes_topsort = ast_utils.parse_order(ast)
	assert(ast_nodes_topsort, "cannot represent snippet: contains circular dependencies")
	for _, node in ipairs(ast_nodes_topsort) do
		to_node(node, state)
	end

	return ast.parsed
end

return M
