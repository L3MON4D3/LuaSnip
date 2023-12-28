local M = {}

local opt_mt = {}
function M.new_opt(ref)
	return setmetatable({ ref = ref }, opt_mt)
end

function M.is_opt(t)
	return getmetatable(t) == opt_mt
end

return M
