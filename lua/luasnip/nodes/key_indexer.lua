local M = {}

---@class LuaSnip.KeyIndexer
---@field key string

local key_mt = {}

--- Create a key indexer
---@param key string
---@return LuaSnip.KeyIndexer
function M.new_key(key)
	return setmetatable({ key = key }, key_mt)
end

---@return boolean
function M.is_key(t)
	return getmetatable(t) == key_mt
end

return M
