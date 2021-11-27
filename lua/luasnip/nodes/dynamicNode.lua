local DynamicNode = require("luasnip.nodes.node").Node:new()
local util = require("luasnip.util.util")
local Node = require("luasnip.nodes.node").Node
local types = require("luasnip.util.types")
local events = require("luasnip.util.events")
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

function DynamicNode:input_enter()
	self.active = true
	self.mark:update_opts(self.parent.ext_opts[self.type].active)

	self:event(events.enter)
end

function DynamicNode:input_leave()
	self:event(events.leave)

	self:update_dependents()
	self.active = false
	self.mark:update_opts(self.parent.ext_opts[self.type].passive)
end

local function snip_init(self, snip)
	snip.parent = self.parent
	snip.env = self.parent.env

	snip.ext_opts = util.increase_ext_prio(
		vim.deepcopy(self.parent.ext_opts),
		conf.config.ext_prio_increase
	)
	snip.snippet = self.parent.snippet
	snip:subsnip_init()
end

function DynamicNode:get_static_text()
	-- cache static_text, no need to recalculate function.
	if not self.static_text then
		local tmp = self.fn(
			self:get_static_args(),
			self.parent,
			nil,
			unpack(self.user_args)
		)
		snip_init(self, tmp)
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
		local success, tmp = pcall(
			self.fn,
			self:get_static_args(),
			self.parent,
			nil,
			unpack(self.user_args)
		)
		if not success then
			local snip = util.find_outer_snippet(self)
			print(errorstring:format(self.indx, snip.name, tmp))
			self.docstring = { "" }
		else
			-- set pos for util.string_wrap().
			snip_init(self, tmp)
			tmp.pos = self.pos
			self.docstring = tmp:get_docstring()
		end
	end
	return self.docstring
end

-- DynamicNode's don't have static text, nop these.
function DynamicNode:put_initial(_) end

function DynamicNode:indent(_) end

function DynamicNode:expand_tabs(_) end

function DynamicNode:jump_into(dir, no_move)
	if self.active then
		self:input_leave()
		if dir == 1 then
			return self.next:jump_into(dir, no_move)
		else
			return self.prev:jump_into(dir, no_move)
		end
	else
		self:input_enter()
		return self.snip:jump_into(dir, no_move)
	end
end

function DynamicNode:update()
	local tmp
	self.last_args = self:get_args()
	if self.snip then
		-- build new snippet before exiting, markers may be needed for construncting.
		tmp = self.fn(
			self.last_args,
			self.parent,
			self.snip.old_state,
			unpack(self.user_args)
		)
		self.snip:exit()
		self.snip = nil

		-- enters node.
		self.parent:set_text(self, { "" })
	else
		-- also enter node here.
		self.parent:enter_node(self.indx)
		tmp = self.fn(self.last_args, self.parent, nil, unpack(self.user_args))
	end

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
	tmp.snippet = self.parent.snippet
	tmp.mark = self.mark:copy_pos_gravs(
		vim.deepcopy(self.parent.ext_opts[types.snippetNode].passive)
	)
	tmp.dependents = self.dependents

	tmp:populate_argnodes()
	tmp:subsnip_init()

	if vim.o.expandtab then
		tmp:expand_tabs(util.tab_width())
	end
	tmp:indent(self.parent.indentstr)

	self.parent:enter_node(self.indx)
	tmp:put_initial(self.mark:pos_begin_raw())
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
	self.active = false
end

function DynamicNode:set_ext_opts(name)
	self.mark:update_opts(self.parent.ext_opts[self.type][name])
	self.snip:set_ext_opts(name)
end

function DynamicNode:store()
	self.snip:store()
end

function DynamicNode:update_restore()
	-- only restore snippet if arg-values still match.
	if self.snip and vim.deep_equal(self:get_args(), self.last_args) then
		self.snip.mark = self.mark:copy_pos_gravs(
			vim.deepcopy(self.parent.ext_opts[types.snippetNode].passive)
		)
		self.parent:enter_node(self.indx)
		self.snip:put_initial(self.mark:pos_begin_raw())
		self.snip:update_restore()
	else
		self:update()
	end
end

return {
	D = D,
}
