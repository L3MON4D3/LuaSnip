local InsertNode = require'luasnip.nodes.node'.Node:new()
local ExitNode = InsertNode:new()
local util = require'luasnip.util.util'
local config = require'luasnip.config'

local function I(pos, static_text)
	if pos == 0 then
		return ExitNode:new{pos = pos, static_text = static_text, markers = {}, dependents = {}, type = 1}
	else
		return InsertNode:new{pos = pos, static_text = static_text, markers = {}, dependents = {}, type = 1, inner_active = false}
	end
end

function ExitNode:input_enter()
	-- Text written in the ExitNode does not belong to snippet.
	self:set_from_rgrav(self.pos == -1)
	self:set_to_rgrav(self.pos == -1)
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), 'n', true)
	-- SELECT snippet text only when there is text to select (more oft than not there isnt).
	util.normal_move_on_mark_insert(self.markers[1])
end

function ExitNode:input_leave()
	-- undo setting rgrav in i_e here.
	self:set_from_rgrav(self.pos ~= -1)
	-- Make sure to jump on insert mode.
	if vim.api.nvim_get_mode().mode == 's' then
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>i", true, false, true), 'n', true)
	end
end

function ExitNode:jump_into(dir)
	if not config.config.history then
		self:input_enter()
		if (dir == 1 and not self.next) or (dir == -1 and not self.prev) then
			Luasnip_current_nodes[vim.api.nvim_get_current_buf()] = nil
		else
			Luasnip_current_nodes[vim.api.nvim_get_current_buf()] = self
		end
	else
		InsertNode.jump_into(self, dir)
	end
end

function InsertNode:input_enter(no_move)
	if not no_move then
		self.parent:enter_node(self.indx)

		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), 'n', true)
		-- SELECT snippet text only when there is text to select (more oft than not there isnt).
		if not util.mark_pos_equal(self.markers[2], self.markers[1]) then
			util.normal_move_on_mark(self.markers[1])
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("v", true, false, true), 'n', true)
			util.normal_move_before_mark(self.markers[2])
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("o<C-G>", true, false, true), 'n', true)
		else
			util.normal_move_on_mark_insert(self.markers[1])
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
				self.next:jump_into(dir)
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
				self.prev:jump_into(dir)
			else
				return false
			end
		end
	else
		self:input_enter(no_move)
		Luasnip_current_nodes[vim.api.nvim_get_current_buf()] = self
	end
	return true
end

function InsertNode:jump_from(dir)
	if dir == 1 then
		if self.inner_first then
			self.inner_active = true
			self.inner_first:jump_into(dir)
		else
			if self.next then
				self:input_leave()
				self.next:jump_into(dir)
			end
		end
	else
		if self.inner_last then
			self.inner_active = true
			self.inner_last:jump_into(dir)
		else
			if self.prev then
				self:input_leave()
				self.prev:jump_into(dir)
			end
		end
	end
end

function InsertNode:input_leave()
	self:update_dependents()

	-- Make sure to jump on insert mode.
	if vim.api.nvim_get_mode().mode == 's' then
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>i", true, false, true), 'n', true)
	end
end

function InsertNode:exit()
	self.inner_first = nil
	self.inner_last = nil
	self.inner_active = false
end

return {
	I = I
}
