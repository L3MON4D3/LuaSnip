local sNode = require("luasnip.nodes.snippet")
local ast_utils = require("luasnip.util.parser.ast_utils")
local ast_parser = require("luasnip.util.parser.ast_parser")
local parse = require("vim.lsp.parser").parse
local Str = require("luasnip.util.str")
local functions = require("luasnip.util.functions")

local M = {}

function M.parse_snippet(context, body, opts)
	opts = opts or {}

	local lines = vim.split(body, "\n")
	Str.process_multiline(lines, opts)
	body = table.concat(lines, "\n")

	local ast = parse(body)

	if type(context) == "number" then
		return sNode.SN(context, ast_parser.to_node(ast))
	end
	if type(context) == "nil" then
		return ast_parser.to_node(ast)
	end

	ast_utils.fix_zero(ast)
	if type(context) == "string" then
		context = { trig = context }
	end
	context.docstring = body

	return sNode.S(context, ast_parser.to_node(ast))
end

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
		var_map[varname] = functions.eval_vim(body:sub(from + 1, to - 1))
		processed_to = to + 1
	end

	return var_map, var_string
end

function M.parse_snipmate(body)
	local new_vars
	new_vars, body = backticks_to_variable(body)
	local ast = parse(body)
	ast_utils.fix_zero(ast)

	return ast_parser.to_node(ast, {
		var_functions = new_vars,
	})
end

return M
