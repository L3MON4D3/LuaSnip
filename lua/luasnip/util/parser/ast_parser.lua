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

local function var_func(ast)
	local varname = ast.name

	local transform_func
	if ast.transform then
		transform_func = ast_utils.apply_transform(ast.transform)
	else
		transform_func = util.id
	end

	return function(_, parent, _, variable_default)
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

		-- quicker than checking `lines` in some way.
		if not v then
			-- the variable is not defined:
			-- insert the variable's name as a placeholder.
			return sNode.SN(nil, { iNode.I(1, varname) })
		end
		if #lines == 0 or (#lines == 1 and #lines[1] == 0) then
			-- The variable is empty.

			-- default passed as user_arg, rationale described in
			-- types.VARIABLE-to_node_func.
			if variable_default then
				return variable_default
			else
				-- lines might still just be {} (#lines == 0).
				lines = { "" }
			end
		end

		-- v exists and has no default, return the (maybe modified) lines.
		return sNode.SN(nil, { tNode.T(transform_func(lines)) })
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

local function placeholder_func(_, parent, _, placeholder_snip)
	local env = parent.snippet.env
	-- is_interactive needs env to determine interactiveness.
	-- env is passed through to all following is_interactive calls.
	if not placeholder_snip:is_interactive(env) then
		-- this placeholder only contains text or (transformed)
		-- variables, so an insertNode can be generated from its
		-- contents.
		-- create new snippet that only contains the parsed snippetNode, so we
		-- can `fake_expand` and `get_static_text()` it.
		local snippet = sNode.S("", placeholder_snip)

		-- get active env from snippet.
		snippet:fake_expand({ env = env })
		local iText = snippet:get_static_text()

		-- no need to un-escape iText, that was already done.
		return sNode.SN(nil, iNode.I(1, iText))
	end

	return sNode.SN(
		nil,
		session.config.parser_nested_assembler(1, placeholder_snip)
	)
end

---If this tabstop-node (CHOICE, TABSTOP or PLACEHOLDER) is a copy of another,
---set that up and return, otherwise return false.
---@param ast table: ast-node.
---@return boolean: whether the node is now parsed.
local function tabstop_node_copy_inst(ast)
	local existing_tabstop_ast_node = ast.copies
	if existing_tabstop_ast_node then
		-- this tabstop is a mirror of an already-parsed tabstop/placeholder.
		ast.parsed =
			fNode.F(copy_func(ast), { existing_tabstop_ast_node.parsed })
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
			-- we cannot place a dynamicNode as $0.
			-- But all valid ${0:some nodes here} contain just text inside
			-- them, so this works :)
			node = iNode.I(ast.tabstop, _split(ast.children[1].esc))
		else
			local snip = sNode.SN(1, ast2luasnip_nodes(ast.children))
			node = dNode.D(ast.tabstop, placeholder_func, {}, {
				-- pass snip here, again to preserve references to other tables.
				user_args = { snip },
			})
		end

		ast.parsed = node
	end,
	[types.VARIABLE] = function(ast, state)
		local var = ast.name

		local default
		if ast.children then
			default = sNode.SN(nil, ast2luasnip_nodes(ast.children))
		end

		local fn
		local is_interactive_fn
		if state.var_functions[var] then
			fn, is_interactive_fn = unpack(state.var_functions[var])
		else
			fn = var_func(ast)
			-- override the regular `is_interactive` to accurately determine
			-- whether the snippet produced by the dynamicNode is interactive
			-- or not. This is important when a variable is wrapped inside a
			-- placeholder: ${1:$TM_SELECTED_TEXT}
			-- With variable-environments we cannot tell at parse-time whether
			-- the dynamicNode will be just text, an insertNode or some other
			-- nodes(the default), so that has to happen at runtime now.
			is_interactive_fn = function(_, env)
				local var_value = env[var]

				if not var_value then
					-- inserts insertNode.
					return true
				end

				-- just wrap it for more uniformity.
				if type(var_value) == "string" then
					var_value = { var_value }
				end

				if
					(#var_value == 1 and #var_value[1] == 0)
					or #var_value == 0
				then
					-- var is empty, default is inserted.
					-- if no default, it's not interactive (an empty string is inserted).
					return default and default:is_interactive()
				end

				-- variable is just inserted, not interactive.
				return false
			end
		end

		local d = dNode.D(ast.potential_tabstop, fn, {}, {
			-- TRICKY!!!!
			-- Problem: if the default is passed to the dynamicNode-function via lambda-capture, the
			-- copy-routine, which will run on expansion, cannot associate these
			-- nodes inside the passed nodes with the ones that are inside the
			-- snippet.
			-- For example, if `default` contains a functionNode which relies on
			-- an insertNode within the snippet, it has the insertNode as an
			-- argnode stored inside it. During copy, the copied insertNode (eg
			-- a pointer to it) has to be inserted at this position as well,
			-- otherwise there might be bugs (the snippet thinks the argnode is
			-- present, but it isn't).
			--
			-- This means that these nodes may not be passed as a simple
			-- lambda-capture (!!).
			-- I don't really like this, it can lead to very subtle errors (not
			-- in this instance, but needing to do this in general).
			--
			-- TODO: think about ways to avoid this. OTOH, this is almost okay,
			-- just needs to be documented a bit.
			--
			-- `default` is potentially nil.
			user_args = { default },
		})
		d.is_interactive = is_interactive_fn

		-- if the variable is preceded by \n<indent>, the indent is applied to
		-- all lines of the variable (important for eg. TM_SELECTED_TEXT).
		if ast.previous_text ~= nil and #ast.previous_text > 1 then
			local last_line_indent =
				ast.previous_text[#ast.previous_text]:match("^%s+$")
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

				-- adjust current d's jump-position..
				d.pos = 1
				-- ..so it has the correct position when wrapped inside a
				-- snippetNode.
				d = sNode.ISN(ast.potential_tabstop, { d }, indentstring)
			end
		end

		ast.parsed = d
	end,
}

--- Converts any ast into luasnip-nodes.
--- Snippets return a table of nodes, those can be used like the return-value of `fmt`.
---@param ast table: AST, as generated by `require("vim.lsp._snippet").parse`
---@param state table:
--- - `var_functions`: table, string -> {dNode-fn, is_interactive_fn}
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
--- - `var_functions`: table, string -> {dNode-fn, is_interactive_fn}
---   For now, only used when parsing snipmate-snippets.
---@return table: list of luasnip-nodes.
function M.to_luasnip_nodes(ast, state)
	state = state or {}
	state.var_functions = state.var_functions or {}

	ast_utils.give_vars_potential_tabstop(ast)

	-- fix disallowed $0 in snippet.
	-- TODO(logging): report changes here.
	ast_utils.fix_zero(ast)

	-- Variables need the text just in front of them to determine whether to
	-- indent all lines of the Variable.
	ast_utils.give_vars_previous_text(ast)

	local ast_nodes_topsort = ast_utils.parse_order(ast)
	assert(
		ast_nodes_topsort,
		"cannot represent snippet: contains circular dependencies"
	)
	for _, node in ipairs(ast_nodes_topsort) do
		to_node(node, state)
	end

	return ast.parsed
end

return M
