local node_names = require("luasnip.util.types").names_pascal_case

---@enum LuaSnip.EventType
local EventType = {
	enter = 1,
	leave = 2,
	change_choice = 3,
	pre_expand = 4,
}

local M = setmetatable({}, { __index = EventType })

---@param node_type LuaSnip.NodeType
---@param event_id LuaSnip.EventType
---@return string
function M.to_string(node_type, event_id)
	if event_id == EventType.change_choice then
		return "ChangeChoice"
	elseif event_id == EventType.pre_expand then
		return "PreExpand"
	else
		return node_names[node_type]
			.. (event_id == EventType.enter and "Enter" or "Leave")
	end
end

return M
