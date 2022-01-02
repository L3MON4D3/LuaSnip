local Dictionary = {}

local function new(o)
	return setmetatable(o or {}, {
		__index = Dictionary,
	})
end

function Dictionary:set(path, value)
	-- Insp(path)
	-- print("val: ", value)
	local current_table = self
	for i = 1, #path - 1 do
		local crt_key = path[i]
		if not current_table[crt_key] then
			current_table[crt_key] = {}
		end
		current_table = current_table[crt_key]
	end
	current_table[path[#path]] = value
end

function Dictionary:get(path)
	local current_table = self
	for _, v in ipairs(path) do
		if not current_table[v] then
			return nil
		end
		current_table = current_table[v]
	end
	-- may not be a table.
	return current_table
end

function Dictionary:find_all(path, key)
	local res = {}
	local to_search = { self:get(path) }
	if not to_search[1] then
		return nil
	end

	-- weird hybrid of depth- and breadth-first search for key, collect values in res.
	local search_index = 1
	local search_size = 1
	while search_size > 0 do
		for k, v in pairs(to_search[search_index]) do
			if k == key then
				res[#res + 1] = v
			else
				to_search[search_index + search_size] = v
				search_size = search_size + 1
			end
		end
		search_index = search_index + 1
		search_size = search_size - 1
	end

	return res
end

return {
	new = new,
}
