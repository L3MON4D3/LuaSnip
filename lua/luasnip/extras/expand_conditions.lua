local M = {}

-----------------------
-- CONDITION OBJECTS --
-----------------------
local memoization_mt = {
	-- logic operators
	-- not
	__unm  = function(o1)    return function(...) return not o1(...)      end end,
	-- or
	__add  = function(o1,o2) return function(...) return o1(...) or  o2(...) end end,
	-- and
	__mul  = function(o1,o2) return function(...) return o1(...) and o2(...) end end,
	-- xnor
	__eq   = function(o1,o2) return function(...) return o1(...) == o2(...) end end,
	-- use table like a function by overloading __call
	__call = function(tab, line_to_cursor, matched_trigger, captures)
		if not tab.mem or tab.invalidate(tab, line_to_cursor, matched_trigger, captures) then
			tab.mem = tab.func(line_to_cursor, matched_trigger, captures)
		end
		return tab.mem
	end
}
-- low level factory
-- invalidate(table) -> bool: decides if the memoization should be invalidated,
-- can store state in table
-- TODO provide invalidate defaults (buffer, cursor, changes, none)
function M.memoization_factory(func, invalidate)
	-- always invalidare by default
	invalidate = invalidate or function() return true end
	return setmetatable({func=func, invalidate=invalidate}, memoization_mt)
end

-------------
-- PRESETS --
-------------
local function line_begin(line_to_cursor, matched_trigger)
	-- +1 because `string.sub("abcd", 1, -2)` -> abc
	return line_to_cursor:sub(1, -(#matched_trigger + 1)):match("^%s*$")
end
function M.line_begin() return M.memoization_factory(line_begin, nil) -- TODO invalidation function
end

local function line_end(line_to_cursor)
	local line = vim.api.nvim_get_current_line()
	return #line_to_cursor == #line
end
function M.line_end() return M.memoization_factory(line_end, nil) -- TODO invalidation function
end

return M
