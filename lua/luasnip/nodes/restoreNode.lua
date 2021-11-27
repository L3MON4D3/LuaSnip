-- restoreNode is implemented similarly to dynamicNode, only that it gets the snippetNode not from some function, but from self.snip.stored[key].

local Node = require("luasnip.nodes.node").Node
local RestoreNode = Node:new()
local types = require("luasnip.util.types")
local events = require("luasnip.util.events")
local util = require("luasnip.util.util")
local conf = require("luasnip.config")
local mark = require("luasnip.util.mark").mark

local function R(pos, key)
	return RestoreNode:new({
		pos = pos,
		key = key,
		mark = nil,
		type = types.snippetNode,
		dependents = {},
	})
end

function RestoreNode:exit()
	self.mark:clear()
	-- snip should exist if exit is called.
	self.snip:store()
	-- will be copied on restore, no need to copy here too.
	self.parent.snippet.stored[self.key] = self.snip
	self.snip:exit()
	self.active = false
end


function RestoreNode:input_enter()
	self.active = true
	self.mark:update_opts(self.parent.ext_opts[self.type].active)

	self:event(events.enter)
end

function RestoreNode:input_leave()
	self:event(events.leave)

	self:update_dependents()
	self.active = false
	self.mark:update_opts(self.parent.ext_opts[self.type].passive)
end

-- don't need these, will be done in put_initial.
function RestoreNode:subsnip_init() end

function RestoreNode:indent(_) end

function RestoreNode:expand_tabs(_) end

-- will be called when before expansion but after snip.parent was initialized.
-- Get the actual snippetNode here.
function RestoreNode:put_initial(pos)
	local tmp = self.parent.snippet.stored[self.key]:copy()

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
	tmp.dependents = self.dependents

	tmp:populate_argnodes()
	tmp:subsnip_init()

	if vim.o.expandtab then
		tmp:expand_tabs(util.tab_width())
	end
	tmp:indent(self.parent.indentstr)

	-- correctly set extmark for node.
	-- does not modify ext_opts[node.type].
	local mark_opts = vim.tbl_extend("keep", {
		right_gravity = false,
		end_right_gravity = false,
	}, self.parent.ext_opts[types.snippetNode].passive)

	local old_pos = vim.deepcopy(pos)
	tmp:put_initial(pos)
	tmp.mark = mark(old_pos, pos, mark_opts)
	tmp:set_old_text()

	self.snip = tmp
end

-- the same as DynamicNode.
function RestoreNode:jump_into(dir, no_move)
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

function RestoreNode:set_ext_opts(name)
	self.mark:update_opts(self.parent.ext_opts[self.type][name])
	self.snip:set_ext_opts(name)
end

function RestoreNode:get_static_text()
	-- cache static_text, no need to recalculate function.
	if not self.static_text then
		self.static_text = self.parent.snippet.stored[self.key]:get_static_text()
	end
	return self.static_text
end

function RestoreNode:set_mark_rgrav(val_begin, val_end)
	Node.set_mark_rgrav(self, val_begin, val_end)
	-- snip is set in put_initial, before calls to that set_mark_rgrav() won't be called.
	self.snip:set_mark_rgrav(val_begin, val_end)
end


function RestoreNode:store() end

function RestoreNode:update_restore() end

return {
	R = R
}
