local InsertNode = require("luasnip.nodes.node").Node:new()
local ExitNode = InsertNode:new()
local util = require("luasnip.util.util")
local types = require("luasnip.util.types")
local events = require("luasnip.util.events")
local session = require("luasnip.session")
local extend_decorator = require("luasnip.util.extend_decorator")

local function I(pos, static_text, opts)
	static_text = util.to_string_table(static_text)

	if pos == 0 then
		return ExitNode:new({
			pos = pos,
			static_text = static_text,
			mark = nil,
			dependents = {},
			type = types.exitNode,
			-- will only be needed for 0-node, -1-node isn't set with this.
			ext_gravities_active = { false, false },
		}, opts)
	else
		return InsertNode:new({
			pos = pos,
			static_text = static_text,
			mark = nil,
			dependents = {},
			type = types.insertNode,
			inner_active = false,
		}, opts)
	end
end
extend_decorator.register(I, { arg_indx = 3 })

function ExitNode:input_enter(no_move, dry_run)
	if dry_run then
		return
	end

	-- Don't enter node for -1-node, it isn't in the node-table.
	if self.pos == 0 then
		InsertNode.input_enter(self, no_move, dry_run)
	else
		-- -1-node:
		self:set_mark_rgrav(true, true)
		if not no_move then
			local mark_begin_pos = self.mark:pos_begin_raw()

			if vim.fn.mode() == "i" then
				util.insert_move_on(mark_begin_pos)
			else
				vim.api.nvim_feedkeys(
					vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
					"n",
					true
				)
				util.normal_move_on_insert(mark_begin_pos)
			end
		end

		self:event(events.enter)
	end
end

function ExitNode:input_leave(no_move, dry_run)
	if dry_run then
		return
	end

	if self.pos == 0 then
		InsertNode.input_leave(self, no_move, dry_run)
	else
		self:event(events.leave)
	end
end

function ExitNode:jump_into(dir, no_move, dry_run)
	if not session.config.history then
		self:input_enter(no_move, dry_run)
		if (dir == 1 and not self.next) or (dir == -1 and not self.prev) then
			if self.pos == 0 then
				-- leave instantly, self won't be active snippet.
				self:input_leave(no_move, dry_run)
			end
			return nil
		else
			return self
		end
	else
		-- if no next node, return self as next current node.
		return InsertNode.jump_into(self, dir, no_move, dry_run) or self
	end
end

function ExitNode:_update_dependents() end
function ExitNode:update_dependents() end
function ExitNode:update_all_dependents() end

function ExitNode:_update_dependents_static() end
function ExitNode:update_dependents_static() end
function ExitNode:update_all_dependents_static() end
function ExitNode:is_interactive()
	return true
end

function InsertNode:input_enter(no_move, dry_run)
	if dry_run then
		return
	end

	self.visited = true
	self.mark:update_opts(self.ext_opts.active)

	if not no_move then
		self.parent:enter_node(self.indx)

		-- SELECT snippet text only when there is text to select (more oft than not there isnt).
		local mark_begin_pos, mark_end_pos = self.mark:pos_begin_end_raw()
		if not util.pos_equal(mark_begin_pos, mark_end_pos) then
			util.any_select(mark_begin_pos, mark_end_pos)
		else
			-- if current and target mode is INSERT, there's no reason to leave it.
			if vim.fn.mode() == "i" then
				util.insert_move_on(mark_begin_pos)
			else
				-- mode might be VISUAL or something else, but <Esc> always leads to normal.
				vim.api.nvim_feedkeys(
					vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
					"n",
					true
				)
				util.normal_move_on_insert(mark_begin_pos)
			end
		end
	else
		self.parent:enter_node(self.indx)
	end

	self:event(events.enter)
end

-- only necessary for insertNodes, inner_active (unlike `active`) does not occur
-- in other nodes.
-- Since insertNodes don't have `active`, we can use the dry_run.active-field
-- for this.
function InsertNode:init_dry_run_inner_active(dry_run)
	if dry_run and dry_run.active[self] == nil then
		dry_run.active[self] = self.inner_active
	end
end
function InsertNode:is_inner_active(dry_run)
	return (not dry_run and self.inner_active)
		or (dry_run and dry_run.active[self])
end

function InsertNode:jump_into(dir, no_move, dry_run)
	self:init_dry_run_inner_active(dry_run)

	if self:is_inner_active(dry_run) then
		if dir == 1 then
			if self.next then
				if not dry_run then
					self.inner_active = false
					if not session.config.history then
						self.inner_first = nil
						self.inner_last = nil
					end
				else
					dry_run.active[self] = false
				end

				self:input_leave(no_move, dry_run)
				return self.next:jump_into(dir, no_move, dry_run)
			else
				return nil
			end
		else
			if self.prev then
				if not dry_run then
					self.inner_active = false
					if not session.config.history then
						self.inner_first = nil
						self.inner_last = nil
					end
				else
					dry_run.active[self] = false
				end

				self:input_leave(no_move, dry_run)
				return self.prev:jump_into(dir, no_move, dry_run)
			else
				return nil
			end
		end
	else
		self:input_enter(no_move, dry_run)
		return self
	end
end

function InsertNode:jump_from(dir, no_move, dry_run)
	self:init_dry_run_inner_active(dry_run)

	if dir == 1 then
		if self.inner_first then
			if not dry_run then
				self.inner_active = true
			else
				dry_run.active[self] = true
			end

			return self.inner_first:jump_into(dir, no_move, dry_run)
		else
			if self.next then
				self:input_leave(no_move, dry_run)
				return self.next:jump_into(dir, no_move, dry_run)
			else
				-- only happens for exitNodes, but easier to include here
				-- and reuse this impl for them.
				return self
			end
		end
	else
		if self.inner_last then
			if not dry_run then
				self.inner_active = true
			else
				dry_run.active[self] = true
			end

			return self.inner_last:jump_into(dir, no_move, dry_run)
		else
			if self.prev then
				self:input_leave(no_move, dry_run)
				return self.prev:jump_into(dir, no_move, dry_run)
			else
				return self
			end
		end
	end
end

function InsertNode:input_leave(_, dry_run)
	if dry_run then
		return
	end

	self:event(events.leave)

	self:update_dependents()
	self.mark:update_opts(self:get_passive_ext_opts())
end

function InsertNode:exit()
	if self.inner_first then
		self.inner_first:exit()
	end
	self.visible = false
	self.inner_first = nil
	self.inner_last = nil
	self.inner_active = false
	self.mark:clear()
end

function InsertNode:get_docstring()
	-- copy as to not in-place-modify static text.
	return util.string_wrap(self.static_text, rawget(self, "pos"))
end

function InsertNode:is_interactive()
	return true
end

return {
	I = I,
}
