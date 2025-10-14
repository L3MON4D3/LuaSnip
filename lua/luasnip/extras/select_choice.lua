local session = require("luasnip.session")
local ls = require("luasnip")
local node_util = require("luasnip.nodes.util")

local function set_choice_callback(data)
	return function(_, indx)
		if not indx then
			return
		end
		-- feed+immediately execute i to enter INSERT after vim.ui.input closes.
		-- vim.api.nvim_feedkeys("i", "x", false)
		ls.set_choice(indx, {cursor_restore_data = data})
	end
end

local function select_choice()
	assert(
		session.active_choice_nodes[vim.api.nvim_get_current_buf()],
		"No active choiceNode"
	)
	local active = session.current_nodes[vim.api.nvim_get_current_buf()]

	local restore_data = node_util.store_cursor_node_relative(active)
	vim.ui.select(
		ls.get_current_choices(),
		{ kind = "luasnip" },
		set_choice_callback(restore_data)
	)
end

return select_choice
