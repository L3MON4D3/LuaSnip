local InsertNode = require("luasnip.nodes.node").Node:new()
local ExitNode = InsertNode:new()
local util = require("luasnip.util.util")
local config = require("luasnip.config")
local types = require("luasnip.util.types")

local function I(pos, static_text)
	static_text = util.wrap_value(static_text)
	if pos == 0 then
		return ExitNode:new({
			pos = pos,
			static_text = static_text or { "" },
			mark = nil,
			dependents = {},
			type = types.exitNode,
			-- will only be needed for 0-node, -1-node isn't set with this.
			ext_gravities_active = { false, false },
		})
	else
		return InsertNode:new({
			pos = pos,
			static_text = static_text or { "" },
			mark = nil,
			dependents = {},
			type = types.insertNode,
			inner_active = false,
		})
	end
end

function ExitNode:input_enter()
	-- Don't enter node for -1-node, it isn't in the node-table.
	if self.pos == 0 then
		InsertNode.input_enter(self)
		-- -1-node:
	else
		self:set_mark_rgrav(true, true)

		vim.api.nvim_feedkeys(
			vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
			"n",
			true
		)
		util.normal_move_on_insert(util.get_ext_position_begin(self.mark.id))
	end
end

function ExitNode:input_leave()
	if self.pos == 0 then
		InsertNode.input_leave(self)
	end
end

function ExitNode:jump_into(dir)
	if not config.config.history then
		self:input_enter()
		if (dir == 1 and not self.next) or (dir == -1 and not self.prev) then
			return nil
		else
			return self
		end
	else
		return InsertNode.jump_into(self, dir)
	end
end

function InsertNode:input_enter(no_move)
	self.mark:update_opts(self.parent.ext_opts[self.type].active)
	if not no_move then
		self.parent:enter_node(self.indx)

		vim.api.nvim_feedkeys(
			vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
			"n",
			true
		)
		-- SELECT snippet text only when there is text to select (more oft than not there isnt).
		local mark_begin_pos, mark_end_pos = util.get_ext_positions(
			self.mark.id
		)
		if not util.pos_equal(mark_begin_pos, mark_end_pos) then
			util.normal_move_on(mark_begin_pos)
			vim.api.nvim_feedkeys(
				vim.api.nvim_replace_termcodes("v", true, false, true),
				"n",
				true
			)
			util.normal_move_before(mark_end_pos)
			vim.api.nvim_feedkeys(
				vim.api.nvim_replace_termcodes("o<C-G>", true, false, true),
				"n",
				true
			)
		else
			util.normal_move_on_insert(mark_begin_pos)
		end
	else
		self.parent:enter_node(self.indx)
	end
end

function InsertNode:jump_into(dir, no_move)
	if self.inner_active then
		if dir == 1 then
			if self.next then
				self.inner_active = false
				if not config.config.history then
					self.inner_first = nil
					self.inner_last = nil
				end
				self:input_leave()
				return self.next:jump_into(dir)
			else
				return false
			end
		else
			if self.prev then
				self.inner_active = false
				if not config.config.history then
					self.inner_first = nil
					self.inner_last = nil
				end
				self:input_leave()
				return self.prev:jump_into(dir)
			else
				return false
			end
		end
	else
		self:input_enter(no_move)
		return self
	end
end

function InsertNode:jump_from(dir)
	if dir == 1 then
		if self.inner_first then
			self.inner_active = true
			return self.inner_first:jump_into(dir)
		else
			if self.next then
				self:input_leave()
				return self.next:jump_into(dir)
			end
		end
	else
		if self.inner_last then
			self.inner_active = true
			return self.inner_last:jump_into(dir)
		else
			if self.prev then
				self:input_leave()
				return self.prev:jump_into(dir)
			end
		end
	end
end

function InsertNode:input_leave()
	self:update_dependents()
	self.mark:update_opts(self.parent.ext_opts[self.type].passive)
end

function InsertNode:exit()
	self.inner_first = nil
	self.inner_last = nil
	self.inner_active = false
	self.mark:clear()
end

function InsertNode:get_docstring()
	-- copy as to not in-place-modify static text.
	return util.string_wrap(vim.deepcopy(self.static_text), self.pos)
end

return {
	I = I,
}
