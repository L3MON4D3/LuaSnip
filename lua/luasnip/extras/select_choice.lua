local session = require("luasnip.session")
local ls = require("luasnip")
local node_util = require("luasnip.nodes.util")
local feedkeys = require("luasnip.util.feedkeys")

-- in this procedure, make sure that api_leave is called before
-- set_choice_callback exits.
local function set_choice_callback(data)
	return function(_, indx)
		if not indx then
			ls._api_leave()
			return
		end
		-- set_choice restores cursor from before.
		ls._set_choice(indx, { cursor_restore_data = data, skip_update = true })
		ls._api_leave()
	end
end

local function select_choice()
	assert(
		session.active_choice_nodes[vim.api.nvim_get_current_buf()],
		"No active choiceNode"
	)
	local active = session.current_nodes[vim.api.nvim_get_current_buf()]

	ls._api_enter()

	ls._active_update_dependents()

	if not session.active_choice_nodes[vim.api.nvim_get_current_buf()] then
		print("Active choice was removed while updating a dynamicNode.")
		return
	end

	local restore_data = node_util.store_cursor_node_relative(
		active,
		{ place_cursor_mark = true }
	)

	-- make sure all movements are done, otherwise the movements may be put into
	-- the select-dialog.
	feedkeys.enqueue_action(function()
		vim.ui.select(
			ls.get_current_choices(),
			{ kind = "luasnip" },
			set_choice_callback(restore_data)
		)
	end)
end

return select_choice
