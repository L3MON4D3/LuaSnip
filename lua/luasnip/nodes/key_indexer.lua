local M = {}

local key_mt = {}
function M.new_key(key)
	return setmetatable({ key = key }, key_mt)
end

function M.is_key(t)
	return getmetatable(t) == key_mt
end

return M
