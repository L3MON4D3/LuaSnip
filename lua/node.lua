local util = require'util'

local Node = {}

function Node:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

local TextNode = Node:new()
local InsertNode = Node:new()
local FunctionNode = Node:new()
local ChoiceNode = Node:new()
local DynamicNode = Node:new()

local function T(static_text)
	return TextNode:new{static_text = static_text, markers = {}, type = 0}
end

local function I(pos, static_text)
	return InsertNode:new{pos = pos, static_text = static_text, markers = {}, dependents = {}, type = 1}
end

local function F(fn, args, ...)
	return FunctionNode:new{fn = fn, args = args, type = 2,  markers = {},user_args = {...}}
end

local function C(pos, choices)
	return ChoiceNode:new{pos = pos, choices = choices, type = 4, markers = {}, current_choice = 1}
end

local function D(pos, fn, args, ...)
	return DynamicNode:new{pos = pos, fn = fn, args = args, type = 5, markers = {}, user_args = {...}}
end

function Node:has_static_text()
	return self:get_static_text() and not (self:get_static_text()[1] == "" and #self:get_static_text() == 1)
end

function Node:get_static_text()
	return self.static_text
end

function Node:put_initial()
	if self:has_static_text() then
		vim.api.nvim_put(self:get_static_text(), "c", false, true);
	end
end

function TextNode:put_initial()
	vim.api.nvim_put(self:get_static_text(), "c", false, true);
end

function Node:input_enter()
end

function Node:set_from_rgrav(val)
	local pos = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, self.markers[1], {})
	vim.api.nvim_buf_del_extmark(0, Luasnip_ns_id, self.markers[1])
	self.markers[1] = vim.api.nvim_buf_set_extmark(0, Luasnip_ns_id, pos[1], pos[2], {right_gravity = val})
end

function Node:set_to_rgrav(val)
	local pos = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, self.markers[2], {})
	vim.api.nvim_buf_del_extmark(0, Luasnip_ns_id, self.markers[2])
	self.markers[2] = vim.api.nvim_buf_set_extmark(0, Luasnip_ns_id, pos[1], pos[2], {right_gravity = val})
end

function Node:get_text()
	local from = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, self.markers[1], {})
	local to = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, self.markers[2], {})

	-- end-exclusive indexing.
	local lines = vim.api.nvim_buf_get_lines(0, from[1], to[1]+1, false)

	if #lines == 1 then
		lines[1] = string.sub(lines[1], from[2]+1, to[2])
	else
		lines[1] = string.sub(lines[1], from[2]+1, #lines[1])

		-- node-range is end-exclusive.
		lines[#lines] = string.sub(lines[#lines], 1, to[2])
	end
	return lines
end

function Node:exit()
end

function InsertNode:input_enter()
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
	if not util.multiline_equal(self.old_text, self:get_text()) then
		self:update_dependents()
	end
end


function TextNode:input_enter()
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), 'n', true)
	util.normal_move_on_mark_insert(self.markers[1])
end

function Node:input_leave()
end

function Node:update_dependents()
	for _, node in ipairs(self.dependents) do
		node:update()
	end
end

--- CAREFUL, DynamicNode also uses this function!!
function FunctionNode:get_args()
	local args = {}
	for i, node in ipairs(self.args) do
		args[i] = node:get_text()
	end
	return args
end

function DynamicNode:get_args()
	return FunctionNode.get_args(self)
end

function FunctionNode:update()
	self.parent:set_text(self, self.fn(self:get_args(), unpack(self.user_args)))
end

function ChoiceNode:put_initial()
	for _, node in ipairs(self.choices) do
		node.markers = self.markers
		node.markers = self.markers
		if node.type == 3 then
			node:indent(vim.api.nvim_get_current_line())
		end
	end
	self.choices[1]:put_initial()
end

function ChoiceNode:input_enter()
	self.old_text = self:get_text()
	self.choices[self.current_choice]:input_enter()
	Luasnip_active_choice = self
end

function ChoiceNode:input_leave()
	if not util.multiline_equal(self.old_text, self:get_text()) then
		self:update_dependents()
	end
	self.choices[self.current_choice]:input_leave()
	Luasnip_active_choice = nil
end

function ChoiceNode:has_static_text()
	return self.choices[1]:has_static_text()
end

function ChoiceNode:get_static_text()
	return self.choices[1]:get_static_text()
end

function ChoiceNode:change_choice(val)
	-- tear down current choice.
	self.choices[self.current_choice]:input_leave()
	self.choices[self.current_choice]:exit()

	-- clear text.
	Luasnip_active_snippet:set_text(self, {""})
	util.move_to_mark(self.markers[1])
	local tmp = self.current_choice + val
	if tmp < 1 then
		tmp = #self.choices
	elseif tmp > #self.choices then
		tmp = 1
	end
	self.current_choice = tmp
	self.choices[self.current_choice]:put_initial()
	util.move_to_mark(self.markers[1])
	self.choices[self.current_choice]:input_enter()
end

function ChoiceNode:copy()
	local o = vim.deepcopy(self)
	for i, node in ipairs(self.choices) do
		if node.type == 3 or node.type == 4 then
			o.choices[i] = node:copy()
		else
			setmetatable(o.choices[i], getmetatable(node))
		end
	end
	setmetatable(o, getmetatable(self))
	return o
end

function DynamicNode:input_enter()
	self.old_text = self:get_text()
	self.snip:input_enter()
end

function DynamicNode:input_leave()
	if not util.multiline_equal(self.old_text, self:get_text()) then
		self:update_dependents()
	end
	self.snip:input_leave()
end

function DynamicNode:has_static_text()
	return false
end

function DynamicNode:get_static_text()
	return self.snip:get_static_text()
end

function DynamicNode:copy()
	local o = {pos = self.pos, fn = self.fn, args = self.args, type = 5, markers = self.markers, user_args = self.user_args}
	o.snip = self.snip:copy()
	return o
end

function DynamicNode:update()
	if self.snip then
		self.snip:exit()
	end
	self.parent:set_text(self, {""})

	self.snip = self.fn(self:get_args(), unpack(self.user_args))

	util.move_to_mark(self.markers[1])
	self.snip:put_initial()
end

return {
	Node = Node,
	T = T,
	I = I,
	F = F,
	C = C,
	D = D
}
