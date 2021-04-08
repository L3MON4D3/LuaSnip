local InsertNode = require'nodes.node'.Node:new()
local ZeroNode = InsertNode:new()
local util = require'util.util'

local function I(pos, static_text)
	if pos == 0 then
		return ZeroNode:new{pos = pos, static_text = static_text, markers = {}, dependents = {}, type = 1}
	else
		return InsertNode:new{pos = pos, static_text = static_text, markers = {}, dependents = {}, type = 1, active = false}
	end
end

-- function ZeroNode:jump_into(dir)
-- 	-- move to zero-inserts position.
-- 	Luasnip_current_nodes[vim.api.nvim_get_current_buf()] = self
-- 	self:input_enter()
-- 	if dir == 1 then
-- 		if self.next then
-- 			-- jump, but don't move cursor.
-- 			self.next:jump_into(dir, true)
-- 		else
-- 			return false
-- 		end
-- 	else
-- 		if self.prev then
-- 			-- jump, but don't move cursor.
-- 			self.prev:jump_into(dir, true)
-- 		else
-- 			return false
-- 		end
-- 	end
-- end

function ZeroNode:input_enter()
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), 'n', true)
	-- SELECT snippet text only when there is text to select (more oft than not there isnt).
	util.normal_move_on_mark_insert(self.markers[1])
end

function ZeroNode:input_leave()
	-- Make sure to jump on insert mode.
	if vim.api.nvim_get_mode().mode == 's' then
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>i", true, false, true), 'n', true)
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
	if self.active then
		if dir == 1 then
			if self.next then
				self.active = false
				self.next:jump_into(dir)
			else
				return false
			end
		else
			if self.prev then
				self.active = false
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
			self.active = true
			self.inner_first:jump_into()
		else
			if self.next then
				self.next:jump_into(dir)
			end
		end
	else
		if self.inner_last then
			self.active = true
			self.inner_last:jump_into()
		else
			if self.prev then
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

return {
	I = I
}
