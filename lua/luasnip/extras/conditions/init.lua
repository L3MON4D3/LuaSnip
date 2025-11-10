--- A composable condition object, can be used for `condition` in a snippet
--- context.
---
---@class LuaSnip.SnipContext.ConditionObj
---@field func LuaSnip.SnipContext.ConditionFn
---
---@overload fun(line_to_cursor: string, matched_trigger: string, captures: string[]): boolean
---  (note: same signature as `func` field)
---
---@operator unm: LuaSnip.SnipContext.ConditionObj
---@operator add(LuaSnip.SnipContext.Condition): LuaSnip.SnipContext.ConditionObj
---@operator sub(LuaSnip.SnipContext.Condition): LuaSnip.SnipContext.ConditionObj
---@operator mul(LuaSnip.SnipContext.Condition): LuaSnip.SnipContext.ConditionObj
---@operator pow(LuaSnip.SnipContext.Condition): LuaSnip.SnipContext.ConditionObj
---@operator mod(LuaSnip.SnipContext.Condition): LuaSnip.SnipContext.ConditionObj
local ConditionObj = {}
local ConditionObj_mt = {
	__index = ConditionObj,
	-- use table like a function by overloading __call
	__call = function(self, line_to_cursor, matched_trigger, captures)
		return self.func(line_to_cursor, matched_trigger, captures)
	end,
}

--- Wrap the given `condition` function in a composable condition object.
---@param func LuaSnip.SnipContext.Condition
---@return LuaSnip.SnipContext.ConditionObj
function ConditionObj.make_condition(func)
	return setmetatable({ func = func }, ConditionObj_mt)
end

--- Returns a condition object equivalent to `not self(...)`
---@return LuaSnip.SnipContext.ConditionObj
function ConditionObj:inverted()
	return ConditionObj.make_condition(function(...)
		return not self(...)
	end)
end
-- (e.g. `-cond`)
ConditionObj_mt.__unm = ConditionObj.inverted

--- Returns a condition object equivalent to `self(...) or other(...)`
---@param other LuaSnip.SnipContext.Condition
---@return LuaSnip.SnipContext.ConditionObj
function ConditionObj:or_(other)
	return ConditionObj.make_condition(function(...)
		return self(...) or other(...)
	end)
end
-- (e.g. `cond1 + cond2`)
ConditionObj_mt.__add = ConditionObj.or_

--- Returns a condition object equivalent to `self(...) and not other(...)`
---@param other LuaSnip.SnipContext.Condition
---@return LuaSnip.SnipContext.ConditionObj
function ConditionObj:and_not(other)
	return ConditionObj.make_condition(function(...)
		return self(...) and not other(...)
	end)
end
-- (e.g. `cond1 - cond2`)
ConditionObj_mt.__sub = ConditionObj.and_not

--- Returns a condition object equivalent to `self(...) and other(...)`
---@param other LuaSnip.SnipContext.Condition
---@return LuaSnip.SnipContext.ConditionObj
function ConditionObj:and_(other)
	return ConditionObj.make_condition(function(...)
		return self(...) and other(...)
	end)
end
-- (e.g. `cond1 * cond2`)
ConditionObj_mt.__mul = ConditionObj.and_

--- Returns a condition object equivalent to `self(...) ~= other(...)`
---@param other LuaSnip.SnipContext.Condition
---@return LuaSnip.SnipContext.ConditionObj
function ConditionObj:not_same_as(other)
	return ConditionObj.make_condition(function(...)
		return self(...) ~= other(...)
	end)
end
-- (e.g. `cond1 ^ cond2`)
ConditionObj_mt.__pow = ConditionObj.not_same_as

--- Returns a condition object equivalent to `self(...) == other(...)`
---@param other LuaSnip.SnipContext.Condition
---@return LuaSnip.SnipContext.ConditionObj
function ConditionObj:same_as(other)
	return ConditionObj.make_condition(function(...)
		return self(...) == other(...)
	end)
end
-- (e.g. `cond1 % cond2`)
-- This operator might be counter intuitive, but '==' can't be used as it must
-- return a boolean. It's best to use something weird (doesn't have to be used)
ConditionObj_mt.__mod = ConditionObj.same_as

return ConditionObj
