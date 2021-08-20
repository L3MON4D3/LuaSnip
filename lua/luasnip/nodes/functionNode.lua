local FunctionNode = require("luasnip.nodes.node").Node:new()
local util = require("luasnip.util.util")
local types = require("luasnip.util.types")

local function F(fn, args, ...)
	return FunctionNode:new({
		fn = fn,
		args = util.wrap_value(args),
		type = types.functionNode,
		mark = nil,
		user_args = { ... },
	})
end

function FunctionNode:get_args()
	local args = {}
	for i, node in ipairs(self.args) do
		args[i] = util.dedent(node:get_text(), self.parent.indentstr)
	end
	args[#args + 1] = self.parent
	return args
end

function FunctionNode:get_static_args()
	local args = {}
	for i, node in ipairs(self.args) do
		args[i] = util.dedent(node:get_static_text(), self.parent.indentstr)
	end
	args[#args + 1] = self.parent
	return args
end

function FunctionNode:input_enter()
	vim.api.nvim_feedkeys(
		vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
		"n",
		true
	)
	util.normal_move_on_insert(self.mark:pos_begin())
end

local errorstring = [[
Error while evaluating functionNode@%d for snippet '%s':
%s
 
:h luasnip-docstring for more info]]
function FunctionNode:get_static_text()
	-- cache static_text, no need to recalculate function.
	if not self.static_text then
		local success, static_text = pcall(
			self.fn,
			self:get_static_args(),
			unpack(self.user_args)
		)

		if not success then
			local snip = util.find_outer_snippet(self)
			print(errorstring:format(self.indx, snip.name, static_text))
			static_text = { "" }
		end
		self.static_text = util.wrap_value(static_text)
	end
	return self.static_text
end

-- function-text will not stand out in any way in docstring.
FunctionNode.get_docstring = FunctionNode.get_static_text

function FunctionNode:update()
	local text = util.wrap_value(
		self.fn(self:get_args(), unpack(self.user_args))
	)
	if vim.o.expandtab then
		util.expand_tabs(text, util.tab_width())
	end
	-- don't expand tabs in parent.indentstr, use it as-is.
	self.parent:set_text(self, util.indent(text, self.parent.indentstr))
end

-- FunctionNode's don't have static text, nop these.
function FunctionNode:put_initial(_) end

function FunctionNode:indent(_) end

function FunctionNode:expand_tabs(_) end

return {
	F = F,
}
