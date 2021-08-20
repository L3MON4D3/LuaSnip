local util = require("luasnip.util.util")

local Node = {}

function Node:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

function Node:get_static_text()
	return self.static_text
end

function Node:get_docstring()
	return self.static_text
end

function Node:put_initial(pos)
	util.put(self:get_static_text(), pos)
end

function Node:input_enter(no_move)
	self.mark:update_opts(self.parent.ext_opts[self.type].active)
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

function Node:set_mark_rgrav(rgrav_beg, rgrav_end)
	self.mark:update_rgravs(rgrav_beg, rgrav_end)
end

function Node:get_text()
	local from_pos, to_pos = util.get_ext_positions(self.mark.id)

	-- end-exclusive indexing.
	local lines = vim.api.nvim_buf_get_lines(
		0,
		from_pos[1],
		to_pos[1] + 1,
		false
	)

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

function Node:exit()
	self.mark:clear()
end

function Node:input_leave()
	self.mark:update_opts(self.parent.ext_opts[self.type].passive)
end

function Node:update_dependents()
	if not util.multiline_equal(self.old_text, self:get_text()) then
		for _, node in ipairs(self.dependents) do
			node:update()
		end
	end
	self.old_text = self:get_text()
end

function Node:update() end

function Node:expand_tabs(tabwidth)
	util.expand_tabs(self.static_text, tabwidth)
end

function Node:indent(indentstr)
	util.indent(self.static_text, indentstr)
end

function Node:populate_argnodes() end

function Node:subsnip_init() end

Node.ext_gravities_active = { false, true }

return {
	Node = Node,
}
