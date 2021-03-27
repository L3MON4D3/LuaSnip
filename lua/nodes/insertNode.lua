local InsertNode = require'nodes.node'.Node:new()
local ZeroNode = InsertNode:new()
local util = require'util.util'

local function I(pos, static_text)
	return InsertNode:new{pos = pos, static_text = static_text, markers = {}, dependents = {}, type = 1}
end

function ZeroNode:jump_into(dir)
	self:input_enter()
	self:jump_from(dir)
end

function InsertNode:input_enter()
	self.parent:enter_node(self.indx)
	self.old_text = self:get_text()
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
