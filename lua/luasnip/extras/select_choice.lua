local session = require("luasnip.session")
local ls = require("luasnip")

local function set_choice_callback(_, indx)
	if not indx then
		return
	end
	-- feed+immediately execute i to enter INSERT after vim.ui.input closes.
	vim.api.nvim_feedkeys("i", "x", false)
	ls.set_choice(indx)
end

local function select_choice()
	assert(
		session.active_choice_nodes[vim.api.nvim_get_current_buf()],
		"No active choiceNode"
	)
	vim.ui.select(
		ls.get_current_choices(),
		{ kind = "luasnip" },
		set_choice_callback
	)
end

return select_choice
