-- absolute_indexer[0][1][2][3] -> { absolute_insert_position = {0,1,2,3} }

---@class LuaSnip.AbsoluteIndexer: {[integer]: LuaSnip.AbsoluteIndexer}
---@field absolute_insert_position integer[]

---@return LuaSnip.AbsoluteIndexer
local function new()
	return setmetatable({
		absolute_insert_position = {},
	}, {
		__index = function(table, key)
			table.absolute_insert_position[#table.absolute_insert_position + 1] =
				key
			return table
		end,
	})
end

return setmetatable({}, {
	__index = function(_, key)
		-- create new table and index it.
		return new()[key]
	end,
	__call = function(_, ...)
		return {
			-- passing ... to a function passes only the first of the
			-- variable number of args.
			absolute_insert_position = type(...) == "number" and { ... } or ...,
		}
	end,
})
