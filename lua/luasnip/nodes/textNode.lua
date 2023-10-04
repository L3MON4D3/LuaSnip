local node_mod = require("luasnip.nodes.node")
local util = require("luasnip.util.util")
local types = require("luasnip.util.types")
local events = require("luasnip.util.events")
local extend_decorator = require("luasnip.util.extend_decorator")

local TextNode = node_mod.Node:new()

local function T(static_text, opts)
	return TextNode:new({
		static_text = util.to_string_table(static_text),
		mark = nil,
		type = types.textNode,
	}, opts)
end
extend_decorator.register(T, { arg_indx = 2 })

function TextNode:input_enter(no_move, dry_run)
	if dry_run then
		return
	end

	self.mark:update_opts(self.ext_opts.active)
	self.visited = true

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

	self:event(events.enter, no_move)
end

function TextNode:update_all_dependents() end

function TextNode:is_interactive()
	-- a resounding false.
	return false
end

function TextNode:extmarks_valid()
	local from, to = self.mark:pos_begin_end_raw()
	if
		util.pos_cmp(from, to) == 0
		and not (
			#self.static_text == 0
			or (#self.static_text == 1 and #self.static_text[1] == 0)
		)
	then
		-- assume the snippet is invalid if a textNode occupies zero space,
		-- but has text which would occupy some.
		-- This should allow some modifications, but as soon as a textNode is
		-- deleted entirely, we sound the alarm :D
		return false
	end
	return true
end

return {
	T = T,
	textNode = TextNode,
}
