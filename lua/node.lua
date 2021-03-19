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

local function T(static_text)
	return TextNode:new{static_text = static_text, type = 0}
end

local function I(pos, static_text)
	return InsertNode:new{pos = pos, static_text = static_text, dependents = {}, type = 1}
end

local function F(fn, args)
	return FunctionNode:new{fn = fn, args = args, type = 2}
end

function Node:has_static_text()
	return self.static_text and not (self.static_text[1] == "" and #self.static_text == 1)
end

function Node:set_from_rgrav(val)
	local pos = vim.api.nvim_buf_get_extmark_by_id(0, Ns_id, self.from, {})
	self.from = vim.api.nvim_buf_set_extmark(0, Ns_id, pos[1], pos[2], {right_gravity = val})
end

function Node:set_to_rgrav(val)
	local pos = vim.api.nvim_buf_get_extmark_by_id(0, Ns_id, self.to, {})
	self.to = vim.api.nvim_buf_set_extmark(0, Ns_id, pos[1], pos[2], {right_gravity = val})
end

function Node:get_text()
	local from = vim.api.nvim_buf_get_extmark_by_id(0, Ns_id, self.from, {})
	local to = vim.api.nvim_buf_get_extmark_by_id(0, Ns_id, self.to, {})

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

return {
	Node = Node,
	T = T,
	I = I,
	F = F,
}
