local DynamicNode = require("luasnip.nodes.node").Node:new()
local util = require("luasnip.util.util")
local Node = require("luasnip.nodes.node").Node
local types = require("luasnip.util.types")
local conf = require("luasnip.config")

local function D(pos, fn, args, ...)
	return DynamicNode:new({
		pos = pos,
		fn = fn,
		args = util.wrap_value(args),
		type = types.dynamicNode,
		mark = nil,
		user_args = { ... },
		dependents = {},
	})
end

function DynamicNode:get_args()
	local args = {}
	for i, node in ipairs(self.args) do
		args[i] = util.dedent(node:get_text(), self.parent.indentstr)
	end
	args[#args + 1] = self.parent
	return args
end

function DynamicNode:get_args_static()
	local args = {}
	for i, node in ipairs(self.args) do
		args[i] = util.dedent(node:get_static_text(), self.parent.indentstr)
	end
	args[#args + 1] = self.parent
	return args
end

function DynamicNode:input_enter()
	self.active = true
	self.mark:update_opts(self.parent.ext_opts[self.type].active)
end

function DynamicNode:input_leave()
	self:update_dependents()
	self.active = false
	self.mark:update_opts(self.parent.ext_opts[self.type].passive)
end

function DynamicNode:get_static_text()
	-- cache static_text, no need to recalculate function.
	if not self.static_text then
		local tmp = self.fn(self:get_args_static(), nil, unpack(self.user_args))
		self.static_text = tmp:get_static_text()
	end
	return self.static_text
end

local errorstring = [[
Error while evaluating dynamicNode@%d for snippet '%s':
%s
 
:h luasnip-docstring for more info]]
function DynamicNode:get_docstring()
	-- cache static_text, no need to recalculate function.
	if not self.docstring then
		local success, tmp = pcall(self.fn, self:get_args_static(), nil, unpack(self.user_args))
		if not success then
		    local snip = util.find_outer_snippet(self)
		    print(errorstring:format(self.indx, snip.name, tmp))
		    self.docstring = {""}
		else
			self.docstring = util.string_wrap(tmp:get_docstring(), self.pos)
		end
	end
	return self.docstring
end

-- DynamicNode's don't have static text, nop these.
function DynamicNode:put_initial(_) end

function DynamicNode:indent(_) end

function DynamicNode:expand_tabs(_) end

function DynamicNode:jump_into(dir)
	if self.active then
		self:input_leave()
		if dir == 1 then
			self.next:jump_into(dir)
		else
			self.prev:jump_into(dir)
		end
	else
		self:input_enter()
		self.snip:jump_into(dir)
	end
end

function DynamicNode:update()
	local tmp
	if self.snip then
		self.snip:input_leave()
		-- build new snippet before exiting, markers may be needed for construncting.
		tmp = self.fn(
			self:get_args(),
			self.snip.old_state,
			unpack(self.user_args)
		)
		-- enters node.
		self.parent:set_text(self, { "" })
		self.snip:exit()
	else
		-- also enter node here.
		self.parent:enter_node(self.indx)
		tmp = self.fn(self:get_args(), nil, unpack(self.user_args))
	end
	self.snip = nil

	-- act as if snip is directly inside parent.
	tmp.parent = self.parent
	tmp.indx = self.indx

	tmp.next = self
	tmp.prev = self

	tmp.env = self.parent.env
	tmp.ext_opts = tmp.ext_opts
		or util.increase_ext_prio(
			vim.deepcopy(self.parent.ext_opts),
			conf.config.ext_prio_increase
		)
	tmp.mark = self.mark:copy_pos_gravs(
		vim.deepcopy(self.parent.ext_opts[types.snippetNode].passive)
	)
	tmp.dependents = self.dependents

	tmp:populate_argnodes()
	tmp:init_choices()
	tmp:subsnip_init()

	if vim.o.expandtab then
		tmp:expand_tabs(util.tab_width())
	end
	tmp:indent(self.parent.indentstr)

	self.parent:enter_node(self.indx)
	tmp:put_initial(util.get_ext_position_begin(self.mark.id))
	-- Update, tbh no idea how that could come in handy, but should be done.
	tmp:update()

	tmp:set_old_text()

	self.snip = tmp
end

function DynamicNode:set_mark_rgrav(val_begin, val_end)
	Node.set_mark_rgrav(self, val_begin, val_end)
	if self.snip then
		self.snip:set_mark_rgrav(val_begin, val_end)
	end
end

function DynamicNode:exit()
	self.mark:clear()
	-- snip should exist if exit is called.
	self.snip:exit()
end

return {
	D = D,
}
