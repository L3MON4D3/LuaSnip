local InsertNode = require("luasnip.nodes.node").Node:new()
local ExitNode = InsertNode:new()
local util = require("luasnip.util.util")
local types = require("luasnip.util.types")
local events = require("luasnip.util.events")
local session = require("luasnip.session")
local extend_decorator = require("luasnip.util.extend_decorator")

local function I(pos, static_text, opts)
	static_text = util.to_string_table(static_text)

	if pos == 0 then
		return ExitNode:new({
			pos = pos,
			static_text = static_text,
			mark = nil,
			dependents = {},
			type = types.exitNode,
			-- will only be needed for 0-node, -1-node isn't set with this.
			ext_gravities_active = { false, false },
		}, opts)
	else
		return InsertNode:new({
			pos = pos,
			static_text = static_text,
			mark = nil,
			dependents = {},
			type = types.insertNode,
			inner_active = false,
		}, opts)
	end
end
extend_decorator.register(I, { arg_indx = 3 })

function ExitNode:input_enter(no_move)
	-- Don't enter node for -1-node, it isn't in the node-table.
	if self.pos == 0 then
		InsertNode.input_enter(self, no_move)
	else
		-- -1-node:
		self:set_mark_rgrav(true, true)
		if not no_move then
			local mark_begin_pos = self.mark:pos_begin_raw()

			if vim.fn.mode() == "i" then
				util.insert_move_on(mark_begin_pos)
			else
				vim.api.nvim_feedkeys(
					vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
					"n",
					true
				)
				util.normal_move_on_insert(mark_begin_pos)
			end
		end

		self:event(events.enter)
	end
end

function ExitNode:input_leave()
	if self.pos == 0 then
		InsertNode.input_leave(self)
	else
		self:event(events.leave)
	end
end

function ExitNode:jump_into(dir, no_move)
	if not session.config.history then
		self:input_enter(no_move)
		if (dir == 1 and not self.next) or (dir == -1 and not self.prev) then
			if self.pos == 0 then
				-- leave instantly, self won't be active snippet.
				self:input_leave()
			end
			return nil
		else
			return self
		end
	else
		-- if no next node, return self as next current node.
		return InsertNode.jump_into(self, dir, no_move) or self
	end
end

function ExitNode:_update_dependents() end
function ExitNode:update_dependents() end
function ExitNode:update_all_dependents() end

function ExitNode:_update_dependents_static() end
function ExitNode:update_dependents_static() end
function ExitNode:update_all_dependents_static() end
function ExitNode:is_interactive()
	return true
end

function InsertNode:input_enter(no_move)
	self.visited = true
	self.mark:update_opts(self.ext_opts.active)

	if not no_move then
		self.parent:enter_node(self.indx)

		-- SELECT snippet text only when there is text to select (more oft than not there isnt).
		local mark_begin_pos, mark_end_pos = self.mark:pos_begin_end_raw()
		if not util.pos_equal(mark_begin_pos, mark_end_pos) then
			util.any_select(mark_begin_pos, mark_end_pos)
		else
			-- if current and target mode is INSERT, there's no reason to leave it.
			if vim.fn.mode() == "i" then
				util.insert_move_on(mark_begin_pos)
			else
				-- mode might be VISUAL or something else, but <Esc> always leads to normal.
				vim.api.nvim_feedkeys(
					vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
					"n",
					true
				)
				util.normal_move_on_insert(mark_begin_pos)
			end
		end
	else
		self.parent:enter_node(self.indx)
	end

	self:event(events.enter)
end

function InsertNode:jump_into(dir, no_move)
	if self.inner_active then
		if dir == 1 then
			if self.next then
				self.inner_active = false
				if not session.config.history then
					self.inner_first = nil
					self.inner_last = nil
				end
				self:input_leave()
				return self.next:jump_into(dir, no_move)
			else
				return false
			end
		else
			if self.prev then
				self.inner_active = false
				if not session.config.history then
					self.inner_first = nil
					self.inner_last = nil
				end
				self:input_leave()
				return self.prev:jump_into(dir, no_move)
			else
				return false
			end
		end
	else
		self:input_enter(no_move)
		return self
	end
end

function InsertNode:jump_from(dir, no_move)
	if dir == 1 then
		if self.inner_first then
			self.inner_active = true
			return self.inner_first:jump_into(dir, no_move)
		else
			if self.next then
				self:input_leave()
				return self.next:jump_into(dir, no_move)
			else
				-- only happens for exitNodes, but easier to include here
				-- and reuse this impl for them.
				return self
			end
		end
	else
		if self.inner_last then
			self.inner_active = true
			return self.inner_last:jump_into(dir, no_move)
		else
			if self.prev then
				self:input_leave()
				return self.prev:jump_into(dir, no_move)
			else
				return self
			end
		end
	end
end

function InsertNode:input_leave()
	self:event(events.leave)

	self:update_dependents()
	self.mark:update_opts(self:get_passive_ext_opts())
end

function InsertNode:exit()
	if self.inner_first then
		self.inner_first:exit()
	end
	self.visible = false
	self.inner_first = nil
	self.inner_last = nil
	self.inner_active = false
	self.mark:clear()
end

function InsertNode:get_docstring()
	-- copy as to not in-place-modify static text.
	return util.string_wrap(self.static_text, rawget(self, "pos"))
end

function InsertNode:is_interactive()
	return true
end

return {
	I = I,
}
