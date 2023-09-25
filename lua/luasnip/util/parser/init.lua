local sNode = require("luasnip.nodes.snippet")
local ast_parser = require("luasnip.util.parser.ast_parser")
local parse = require("luasnip.util.parser.neovim_parser").parse
local Ast = require("luasnip.util.parser.neovim_ast")
local Str = require("luasnip.util.str")
local functions = require("luasnip.util.functions")
local util = require("luasnip.util.util")
local extend_decorator = require("luasnip.util.extend_decorator")

local M = {}

---Parse snippet represented by `body`.
---@param context (table|string|number|nil):
--- - table|string: treated like the first argument to `ls.snippet`,
---   returns a snippet.
--- - number: Returns a snippetNode, `context` is its' jump-position.
--- - nil: Returns a flat list of luasnip-nodes, to be used however.
---@param body string: the representation of the snippet.
---@param opts table|nil: optional parameters. Valid keys:
--- - `trim_empty`: boolean, remove empty lines from the snippet.
--- - `dedent`: boolean, remove common indent from the snippet's lines.
--- - `variables`: map[string-> (fn()->string)], variables to be used only in this
---   snippet.
---@return table: the snippet, in the representation dictated by the value of
---`context`.
function M.parse_snippet(context, body, opts)
	opts = opts or {}
	if opts.dedent == nil then
		opts.dedent = true
	end
	if opts.trim_empty == nil then
		opts.trim_empty = true
	end

	body = Str.sanitize(body)

	local lines = vim.split(body, "\n")
	Str.process_multiline(lines, opts)
	body = table.concat(lines, "\n")

	local ast
	if body == "" then
		ast = Ast.snippet({
			Ast.text(""),
		})
	else
		ast = parse(body)
	end

	local nodes = ast_parser.to_luasnip_nodes(ast, {
		var_functions = opts.variables,
	})

	if type(context) == "number" then
		return sNode.SN(context, nodes)
	end
	if type(context) == "nil" then
		return nodes
	end

	if type(context) == "string" then
		context = { trig = context }
	end
	context.docstring = body

	return sNode.S(context, nodes)
end
local function context_extend(arg, extend)
	local argtype = type(arg)
	if argtype == "string" then
		arg = { trig = arg }
	end

	if argtype == "table" then
		return vim.tbl_extend("keep", arg, extend or {})
	end

	-- fall back to unchanged arg.
	-- log this, probably.
	return arg
end
extend_decorator.register(
	M.parse_snippet,
	{ arg_indx = 1, extend = context_extend },
	{ arg_indx = 3 }
)

local function backticks_to_variable(body)
	local var_map = {}
	local variable_indx = 1
	local var_string = ""

	local processed_to = 1
	for from, to in Str.unescaped_pairs(body, "`", "`") do
		local varname = "LUASNIP_SNIPMATE_VAR" .. variable_indx
		var_string = var_string
			-- since the first unescaped ` is at from, there is no unescaped `
			-- in body:sub(old_to, from-1). We can therefore gsub occurences of
			-- \`, without worrying about potentially changing something like
			-- \\` (or \\\\`) into \` (\\\`).
			.. body:sub(processed_to, from - 1):gsub("\\`", "`")
			-- `$varname` is unsafe, might lead to something like "my
			-- snip$LUASNIP_SNIPMATE_VAR1pet", where the variable is
			-- interpreted as "LUASNIP_SNIPMATE_VAR1pet".
			-- This cannot happen with curly braces.
			.. "${"
			.. varname
			.. "}"

		-- don't include backticks in vimscript.
		var_map[varname] =
			functions.eval_vim_dynamic(body:sub(from + 1, to - 1))
		processed_to = to + 1
		variable_indx = variable_indx + 1
	end

	-- append remaining characters.
	var_string = var_string .. body:sub(processed_to, -1):gsub("\\`", "`")

	return var_map, var_string
end

function M.parse_snipmate(context, body, opts)
	local new_vars
	new_vars, body = backticks_to_variable(body)

	opts = opts or {}
	opts.variables = {}
	for name, fn in pairs(new_vars) do
		-- created dynamicNode is not interactive.
		opts.variables[name] = { fn, util.no }
	end
	return M.parse_snippet(context, body, opts)
end
extend_decorator.register(
	M.parse_snipmate,
	{ arg_indx = 1, extend = context_extend },
	{ arg_indx = 3 }
)

return M
