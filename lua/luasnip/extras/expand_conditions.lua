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
function M.memoization_factory(func, invalidate)
	-- always invalidare by default
	invalidate = invalidate or function() return true end
	return setmetatable({func=func, invalidate=invalidate}, memoization_mt)
end

-------------------
-- INVAL PRESETS --
-------------------
-- TODO provide invalidate defaults (buffer, cursor, changes, none)
M.inval = {}
-- just a small example to illustrate the usage (will most probably have to be
-- changed)
function M.inval.line(tab, _, _, _, line)
	return tab.line ~= line
end

------------------
-- COND PRESETS --
------------------
local function line_begin(line_to_cursor, matched_trigger)
	-- +1 because `string.sub("abcd", 1, -2)` -> abc
	return line_to_cursor:sub(1, -(#matched_trigger + 1)):match("^%s*$")
end
function M.line_begin()
	-- TODO invalidation function
	return M.memoization_factory(line_begin, nil)
end

local function line_end(line_to_cursor)
	local line = vim.api.nvim_get_current_line()
	return #line_to_cursor == #line
end
function M.line_end()
	-- TODO invalidation function
	return M.memoization_factory(line_end, nil)
end

return M
