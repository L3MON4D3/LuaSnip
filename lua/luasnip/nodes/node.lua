local util = require'luasnip.util.util'

local Node = {}

function Node:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
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

function Node:input_enter(no_move)
end

function Node:jump_into(dir, no_move)
	self:input_enter(no_move)
	Luasnip_current_nodes[vim.api.nvim_get_current_buf()] = self
end

function Node:jump_from(dir)
	self:input_leave()
	if dir == 1 then
		if self.next then
			self.next:jump_into(dir)
		else
			return false
		end
	else
		if self.prev then
			self.prev:jump_into(dir)
		else
			return false
		end
	end
	return true
end

function Node:jumpable(dir)
	if dir == 1 then
		return self.next ~= nil
	else
		return self.prev ~= nil
	end
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

function Node:set_old_text()
	self.old_text = self:get_text()
end

function Node:exit()
end

function Node:input_leave()
end

function Node:update_dependents()
	if not util.multiline_equal(self.old_text, self:get_text()) then
		for _, node in ipairs(self.dependents) do
			node:update()
		end
	end
	self.old_text = self:get_text()
end

function Node:update()
end

return {
	Node = Node,
}
