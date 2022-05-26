local sNode = require("luasnip.nodes.snippet")
local ast_utils = require("luasnip.util.parser.ast_utils")
local ast_parser = require("luasnip.util.parser.ast_parser")
local parse = require("vim.lsp._snippet").parse

local M = {}

function M.parse_snippet(context, body)
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

return M
