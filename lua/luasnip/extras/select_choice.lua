local session = require("luasnip.session")
local ls = require("luasnip")
local node_util = require("luasnip.nodes.util")

-- in this procedure, make sure that api_leave is called before
-- set_choice_callback exits.
local function set_choice_callback(data)
	return function(_, indx)
		if not indx then
			ls._api_leave()
			return
		end
		-- feed+immediately execute i to enter INSERT after vim.ui.input closes.
		-- vim.api.nvim_feedkeys("i", "x", false)
		ls._set_choice(indx, {cursor_restore_data = data})
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
	local restore_data = node_util.store_cursor_node_relative(active, {place_cursor_mark = false})
	vim.ui.select(
		ls.get_current_choices(),
		{ kind = "luasnip" },
		set_choice_callback(restore_data)
	)
end

return select_choice
