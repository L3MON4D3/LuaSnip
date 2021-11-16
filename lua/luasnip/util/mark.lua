local session = require("luasnip.session")

local Mark = {}

function Mark:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

-- opts just like in nvim_buf_set_extmark.
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

local function bytecol_to_utfcol(pos)
	local line = vim.api.nvim_buf_get_lines(0, pos[1], pos[1] + 1, false)
	-- line[1]: get_lines returns table.
	-- use utf16-index.
	local utf16_indx, _ = vim.str_utfindex(line[1] or "", pos[2])
	return { pos[1], utf16_indx }
end

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

function Mark:pos_begin()
	local mark_info = vim.api.nvim_buf_get_extmark_by_id(
		0,
		session.ns_id,
		self.id,
		{ details = false }
	)

	return bytecol_to_utfcol({ mark_info[1], mark_info[2] })
end

function Mark:pos_end()
	local mark_info = vim.api.nvim_buf_get_extmark_by_id(
		0,
		session.ns_id,
		self.id,
		{ details = true }
	)

	return bytecol_to_utfcol({ mark_info[3].end_row, mark_info[3].end_col })
end

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

function Mark:pos_begin_raw()
	local mark_info = vim.api.nvim_buf_get_extmark_by_id(
		0,
		session.ns_id,
		self.id,
		{ details = false }
	)
	return { mark_info[1], mark_info[2] }
end

function Mark:copy_pos_gravs(opts)
	local pos_beg, pos_end = self:pos_begin_end_raw()
	opts.right_gravity = self.opts.right_gravity
	opts.end_right_gravity = self.opts.end_right_gravity
	return mark(pos_beg, pos_end, opts)
end

-- opts just like in nvim_buf_set_extmark.
-- opts as first arg bcs. pos are pretty likely to stay the same.
function Mark:update(opts, pos_begin, pos_end)
	-- if one is changed, the other is likely as well.
	if not pos_begin then
		pos_begin = old_pos_begin
		if not pos_end then
			pos_end = old_pos_end
		end
	end
	-- override with new.
	self.opts = vim.tbl_extend("force", self.opts, opts)
	vim.api.nvim_buf_set_extmark(
		0,
		session.ns_id,
		pos_begin[1],
		pos_begin[2],
		vim.tbl_extend(
			"force",
			self.opts,
			{ id = self.id, end_line = pos_end[1], end_col = pos_end[2] }
		)
	)
end

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

function Mark:update_rgravs(rgrav_beg, rgrav_end)
	-- don't update if nothing would change.
	if
		self.opts.right_gravity ~= rgrav_beg
		or self.opts.end_right_gravity ~= rgrav_end
	then
		self.opts.right_gravity = rgrav_beg
		self.opts.end_right_gravity = rgrav_end
		self:set_opts(self.opts)
	end
end

-- change all opts except rgravs.
function Mark:update_opts(opts)
	local opts_cp = vim.deepcopy(opts)
	opts_cp.right_gravity = self.opts.right_gravity
	opts_cp.end_right_gravity = self.opts.end_right_gravity
	self:set_opts(opts_cp)
end

function Mark:clear()
	vim.api.nvim_buf_del_extmark(0, session.ns_id, self.id)
end

return {
	mark = mark,
}
