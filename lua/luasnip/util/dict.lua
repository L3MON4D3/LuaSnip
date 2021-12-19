local Dictionary = {}

local function new()
	return setmetatable({}, {
		__index = Dictionary
	})
end

function Dictionary:set(path, value)
	local current_table = self
	for i = 1, #path-1 do
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

return {
	new = new
}
