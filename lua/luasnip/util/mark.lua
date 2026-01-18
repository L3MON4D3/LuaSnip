local session = require("luasnip.session")
local util = require("luasnip.util.util")

---@alias LuaSnip.Mark.WhichSide
---| -1 # left side
---|  1 # right side

---@class LuaSnip.Mark Represents an extmark in a buffer.
---@field id? integer Extmark ID
---@field opts vim.api.keyset.set_extmark Extmark options
local Mark = {}

---@return LuaSnip.Mark
function Mark:new(o)
	o = o or { id = nil, opts = {} }
	setmetatable(o, self)
	self.__index = self
	return o
end

---@param pos_begin LuaSnip.RawPos00
---@param pos_end LuaSnip.RawPos00
---@param opts vim.api.keyset.set_extmark
---@return LuaSnip.Mark
local function mark(pos_begin, pos_end, opts)
	return Mark:new({
		id = vim.api.nvim_buf_set_extmark(
			0,
			session.ns_id,
			pos_begin[1],
			pos_begin[2],
			-- override end_* in opts.
			vim.tbl_extend(
				"force",
				opts,
				{ end_line = pos_end[1], end_col = pos_end[2] }
			)
		),
		-- store opts here, can't be queried using nvim_buf_get_extmark_by_id.
		opts = opts,
	})
end

---@param pos LuaSnip.RawPos00
---@return LuaSnip.Pos00
local function bytecol_to_utfcol(pos)
	local line = vim.api.nvim_buf_get_lines(0, pos[1], pos[1] + 1, false)
	-- line[1]: get_lines returns table.
	return { pos[1], util.str_utf32index(line[1] or "", pos[2]) }
end

--- Returns the (utf-32) begin/end positions of the mark.
---@return LuaSnip.Pos00 begin Begin position, (0,0)-indexed
---@return LuaSnip.Pos00 end End position, (0,0)-indexed
function Mark:pos_begin_end()
	local mark_info = vim.api.nvim_buf_get_extmark_by_id(
		0,
		session.ns_id,
		self.id,
		{ details = true }
	)

	return bytecol_to_utfcol({ mark_info[1], mark_info[2] }),
		bytecol_to_utfcol({ mark_info[3].end_row, mark_info[3].end_col })
end

--- Returns the (utf-32) begin position of the mark
---@return LuaSnip.Pos00
function Mark:pos_begin()
	local mark_info = vim.api.nvim_buf_get_extmark_by_id(
		0,
		session.ns_id,
		self.id,
		{ details = false }
	)

	return bytecol_to_utfcol({ mark_info[1], mark_info[2] })
end

--- Returns the (utf-32) end position of the mark
---@return LuaSnip.Pos00
function Mark:pos_end()
	local mark_info = vim.api.nvim_buf_get_extmark_by_id(
		0,
		session.ns_id,
		self.id,
		{ details = true }
	)

	return bytecol_to_utfcol({ mark_info[3].end_row, mark_info[3].end_col })
end

--- Returns the raw (byte) begin/end positions of the mark.
---@return LuaSnip.RawPos00 begin Begin position, (0,0)-indexed
---@return LuaSnip.RawPos00 end End position, (0,0)-indexed
function Mark:pos_begin_end_raw()
	local mark_info = vim.api.nvim_buf_get_extmark_by_id(
		0,
		session.ns_id,
		self.id,
		{ details = true }
	)
	return { mark_info[1], mark_info[2] }, {
		mark_info[3].end_row,
		mark_info[3].end_col,
	}
end

--- Returns the raw (byte) begin position of the mark
---@return LuaSnip.RawPos00
function Mark:pos_begin_raw()
	local mark_info = vim.api.nvim_buf_get_extmark_by_id(
		0,
		session.ns_id,
		self.id,
		{ details = false }
	)
	return { mark_info[1], mark_info[2] }
end

---@param opts vim.api.keyset.set_extmark
---@return LuaSnip.Mark
function Mark:copy_pos_gravs(opts)
	local pos_beg, pos_end = self:pos_begin_end_raw()
	opts.right_gravity = self.opts.right_gravity
	opts.end_right_gravity = self.opts.end_right_gravity
	return mark(pos_beg, pos_end, opts)
end

---@param opts vim.api.keyset.set_extmark
function Mark:set_opts(opts)
	local pos_begin, pos_end = self:pos_begin_end_raw()
	vim.api.nvim_buf_del_extmark(0, session.ns_id, self.id)

	self.opts = opts
	-- set new extmark, current behaviour for updating seems inconsistent,
	-- eg. gravs are reset, deco is kept.
	self.id = vim.api.nvim_buf_set_extmark(
		0,
		session.ns_id,
		pos_begin[1],
		pos_begin[2],
		vim.tbl_extend(
			"force",
			opts,
			{ end_line = pos_end[1], end_col = pos_end[2] }
		)
	)
end

--- Set right-gravity for left & right sides
---@param rgrav_left boolean
---@param rgrav_right boolean
function Mark:set_rgravs(rgrav_left, rgrav_right)
	-- don't update if nothing would change.
	if
		self.opts.right_gravity ~= rgrav_left
		or self.opts.end_right_gravity ~= rgrav_right
	then
		self.opts.right_gravity = rgrav_left
		self.opts.end_right_gravity = rgrav_right
		self:set_opts(self.opts)
	end
end

--- Returns right-gravity for left or right side
---@param which_side LuaSnip.Mark.WhichSide
---@return boolean?
function Mark:get_rgrav(which_side)
	if which_side == -1 then
		return self.opts.right_gravity
	else
		return self.opts.end_right_gravity
	end
end

--- Set right-gravity for left or right side
---@param which_side LuaSnip.Mark.WhichSide
---@param rgrav boolean
function Mark:set_rgrav(which_side, rgrav)
	if which_side == -1 then
		if self.opts.right_gravity == rgrav then
			return
		end
		self.opts.right_gravity = rgrav
	else
		if self.opts.end_right_gravity == rgrav then
			return
		end
		self.opts.end_right_gravity = rgrav
	end
	self:set_opts(self.opts)
end

--- Returns the raw (byte) position of the wanted side
---@param which_side LuaSnip.Mark.WhichSide
---@return LuaSnip.RawPos00
function Mark:get_endpoint(which_side)
	-- simpler for now, look into perf here later.
	local l, r = self:pos_begin_end_raw()
	if which_side == -1 then
		return l
	else
		return r
	end
end

--- Update all opts except right-gravities
---@param opts vim.api.keyset.set_extmark
function Mark:update_opts(opts)
	local opts_cp = vim.deepcopy(opts)
	opts_cp.right_gravity = self.opts.right_gravity
	opts_cp.end_right_gravity = self.opts.end_right_gravity
	self:set_opts(opts_cp)
end

--- Invalidate this mark object only, leave the underlying extmark alone.
function Mark:invalidate()
	self.id = nil
end

--- Delete the underlying extmark if any.
function Mark:clear()
	if self.id then
		vim.api.nvim_buf_del_extmark(0, session.ns_id, self.id)
		-- FIXME(@bew): Should also invalidate the Mark obj? (self.id = nil)
	end
end

return {
	mark = mark,
}
