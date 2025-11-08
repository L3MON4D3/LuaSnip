local M = {}

---@class LuaSnip.OptionalNodeRef
---@field ref LuaSnip.NodeRef

local opt_mt = {}

--- Create an optional node ref
---@param ref LuaSnip.NodeRef
---@return LuaSnip.OptionalNodeRef
function M.new_opt(ref)
	return setmetatable({ ref = ref }, opt_mt)
end

---@return boolean
function M.is_opt(t)
	return getmetatable(t) == opt_mt
end

return M
