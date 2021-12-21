local Node = require("luasnip.nodes.node").Node
local FunctionNode = Node:new()
local util = require("luasnip.util.util")
local node_util = require("luasnip.nodes.util")
local types = require("luasnip.util.types")
local events = require("luasnip.util.events")

local function F(fn, args, ...)
	return FunctionNode:new({
		fn = fn,
		args = node_util.wrap_args(args),
		type = types.functionNode,
		mark = nil,
		user_args = { ... },
	})
end

function FunctionNode:input_enter()
	vim.api.nvim_feedkeys(
		vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
		"n",
		true
	)
	util.normal_move_on_insert(self.mark:pos_begin())

	self:event(events.enter)
end

local errorstring = [[
Error while evaluating functionNode@%d for snippet '%s':
%s
 
:h luasnip-docstring for more info]]
function FunctionNode:get_static_text()
	-- cache static_text, no need to recalculate function.
	if not self.static_text then
		local args = self:get_static_args()
		-- an argnode couldn't be found.
		if not args then
			return { "" }
		end
		local success, static_text = pcall(
			self.fn,
			args,
			self.parent,
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
	self.last_args = self:get_args()
	if not self.last_args then
		return
	end
	local text = util.wrap_value(
		self.fn(self.last_args, self.parent, unpack(self.user_args))
	)
	if vim.o.expandtab then
		util.expand_tabs(text, util.tab_width())
	end
	-- don't expand tabs in parent.indentstr, use it as-is.
	self.parent:set_text(self, util.indent(text, self.parent.indentstr))
end

function FunctionNode:update_restore()
	-- only if args still match.
	if self.static_text and vim.deep_equal(self:get_args(), self.last_args) then
		self.parent:set_text(self, self.static_text)
	else
		self:update()
	end
end

-- FunctionNode's don't have static text, nop these.
function FunctionNode:put_initial(_)
	self.visible = true
end

function FunctionNode:indent(_) end

function FunctionNode:expand_tabs(_) end

function FunctionNode:make_args_absolute(position_so_far)
	self.args_absolute = {}
	node_util.make_args_absolute(self.args, position_so_far, self.args_absolute)
end

function FunctionNode:set_dependents()
	local dict = self.parent.snippet.dependents_dict
	local append_list = vim.list_extend(
		{ "dependents" },
		self.absolute_position
	)
	append_list[#append_list + 1] = "dependent"

	for _, arg in ipairs(self.args_absolute) do
		-- mutates arg! Contains key for dict and this node, from now on.
		dict:set(vim.list_extend(vim.deepcopy(arg), append_list), self)
	end
end

return {
	F = F,
	FunctionNode = FunctionNode,
}
