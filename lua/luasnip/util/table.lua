---Convert set of values to a list of those values.
---@generic T
---@param tbl T|T[]|table<T, boolean>
---@return table<T, boolean>
local function set_to_list(tbl)
	local ls = {}

	for v, _ in pairs(tbl) do
		table.insert(ls, v)
	end

	return ls
end

---Convert value or list of values to a table of booleans for fast lookup.
---@generic T
---@param values T|T[]|table<T, boolean>
---@return table<T, boolean>
local function list_to_set(values)
	if values == nil then
		return {}
	end

	if type(values) ~= "table" then
		return { [values] = true }
	end

	local list = {}
	for _, v in ipairs(values) do
		list[v] = true
	end

	return list
end

return {
	list_to_set = list_to_set,
	set_to_list = set_to_list,
}
