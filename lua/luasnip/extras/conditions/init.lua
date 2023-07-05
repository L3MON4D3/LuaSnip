local M = {}

-----------------------
-- CONDITION OBJECTS --
-----------------------
local condition_mt = {
	-- logic operators
	-- not '-'
	__unm = function(o1)
		return M.make_condition(function(...)
			return not o1(...)
		end)
	end,
	-- or '+'
	__add = function(o1, o2)
		return M.make_condition(function(...)
			return o1(...) or o2(...)
		end)
	end,
	__sub = function(o1, o2)
		return M.make_condition(function(...)
			return o1(...) and not o2(...)
		end)
	end,
	-- and '*'
	__mul = function(o1, o2)
		return M.make_condition(function(...)
			return o1(...) and o2(...)
		end)
	end,
	-- xor '^'
	__pow = function(o1, o2)
		return M.make_condition(function(...)
			return o1(...) ~= o2(...)
		end)
	end,
	-- xnor '%'
	-- might be counter intuitive, but as we can't use '==' (must return bool)
	-- it's best to use something weird (doesn't have to be used)
	__mod = function(o1, o2)
		return function(...)
			return o1(...) == o2(...)
		end
	end,
	-- use table like a function by overloading __call
	__call = function(tab, line_to_cursor, matched_trigger, captures)
		return tab.func(line_to_cursor, matched_trigger, captures)
	end,
}

function M.make_condition(func)
	return setmetatable({ func = func }, condition_mt)
end

return M
