local node_names = require("luasnip.util.types").names_pascal_case

return {
	enter = 1,
	leave = 2,
	change_choice = 3,
	to_string = function(node_type, event_id)
		if event_id == 3 then
			return "ChangeChoice"
		else
			return node_names[node_type]
				.. (event_id == 1 and "Enter" or "Leave")
		end
	end,
}
