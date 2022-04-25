local session = require("luasnip.session")
local util = require("luasnip.util.util")

local function set_choice_callback(_, indx)
	local choice = indx and session.active_choice_node.choices[indx]
	if not choice then
		return
	end
	local new_active = util.no_region_check_wrap(
		session.active_choice_node.set_choice,
		session.active_choice_node,
		choice,
		session.current_nodes[vim.api.nvim_get_current_buf()]
	)
	session.current_nodes[vim.api.nvim_get_current_buf()] = new_active
end

local function active_choice_get_choices_text()
	local choice_lines = {}

	for i, choice in ipairs(session.active_choice_node.choices) do
		choice_lines[i] = table.concat(choice:get_docstring(), "\n")
	end

	return choice_lines
end

local function select_choice()
	assert(session.active_choice_node, "No active choiceNode")
	vim.ui.select(
		active_choice_get_choices_text(),
		{ kind = "luasnip" },
		set_choice_callback
	)
end

return select_choice
