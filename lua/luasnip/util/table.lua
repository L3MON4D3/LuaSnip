---Convert string or list of string to a table of booleans for fast lookup.
---@generic T
---@param values T|T[]|table<T, boolean>
---@return table<T, boolean>
local function normalize_search_table(values)
	if values == nil then
		return {}
	end

	if type(values) ~= "table" then
		return { [values] = true }
	end

	if vim.tbl_islist(values) then
		local new_tbl = {}
		for _, v in ipairs(values) do
			new_tbl[v] = true
		end
		return new_tbl
	end

	return values
end

return {
	normalize_search_table = normalize_search_table,
}
