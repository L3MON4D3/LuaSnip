local util = require("luasnip.util.util")

local Node = {}

function Node:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

function Node:has_static_text()
	return self:get_static_text()
		and not (
			self:get_static_text()[1] == "" and #self:get_static_text() == 1
		)
end

function Node:get_static_text()
	return self.static_text
end

function Node:put_initial(pos)
	if self:has_static_text() then
		util.put(self:get_static_text(), pos)
	end
end

function Node:input_enter(no_move) end

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

function Node:set_mark_rgrav(val_begin, val_end)
	local mark_id = self.mark
	local opts = {
		id = mark_id
	}

	if val_begin ~= nil then
		opts.right_gravity = val_begin
	end

	if val_end ~= nil then
		opts.end_right_gravity = val_end
	end

	-- pos[3] contains old opts-table.
	local info = vim.api.nvim_buf_get_extmark_by_id(
		0,
		Luasnip_ns_id,
		mark_id,
		{details=true}
	)
	opts.end_line = info[3].end_row
	opts.end_col = info[3].end_col
	opts.hl_group = info[3].hl_group
	opts.priority = info[3].priority

	vim.api.nvim_buf_set_extmark(
		0,
		Luasnip_ns_id,
		info[1],
		info[2],
		opts
	)
end

function Node:get_text()
	local from_pos, to_pos = util.get_ext_positions(self.mark)

	-- end-exclusive indexing.
	local lines = vim.api.nvim_buf_get_lines(0, from_pos[1], to_pos[1] + 1, false)

	if #lines == 1 then
		lines[1] = string.sub(lines[1], from_pos[2] + 1, to_pos[2])
	else
		lines[1] = string.sub(lines[1], from_pos[2] + 1, #lines[1])

		-- node-range is end-exclusive.
		lines[#lines] = string.sub(lines[#lines], 1, to_pos[2])
	end
	return lines
end

function Node:set_old_text()
	self.old_text = self:get_text()
end

function Node:exit() end

function Node:input_leave() end

function Node:update_dependents()
	if not util.multiline_equal(self.old_text, self:get_text()) then
		for _, node in ipairs(self.dependents) do
			node:update()
		end
	end
	self.old_text = self:get_text()
end

function Node:update() end

Node.ext_gravities_active = {false, true}

return {
	Node = Node,
}
