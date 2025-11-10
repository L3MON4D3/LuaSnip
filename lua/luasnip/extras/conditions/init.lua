--- A composable condition object. It can be used for `condition` in a snippet
--- context but can also be logically combined with other condition
--- function/object to build complex conditions.
---
--- This makes logical combinations of conditions very readable.
---
--- Compare
--- ```lua
--- local conds = require"luasnip.extras.conditions.expand"
--- ...
--- -- using combinator functions:
--- condition = conds.line_end:or_(conds.line_begin)
--- -- using operators:
--- condition = conds.line_end + conds.line_begin
--- ```
---
--- with the more verbose
---
--- ```lua
--- local conds = require"luasnip.extras.conditions.expand"
--- ...
--- condition = function(...) return conds.line_end(...) or conds.line_begin(...) end
--- ```
---
--- The conditions provided in `show` and `expand` are already condition objects.
--- To create new ones, use:
--- ```lua
--- require("luasnip.extras.conditions").make_condition(condition_fn)
--- ```
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

--- Wrap the given `condition` function into a composable condition object.
---@param func LuaSnip.SnipContext.ConditionFn
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
--- (e.g. `-cond`, implemented as `cond:inverted()`)
ConditionObj_mt.__unm = ConditionObj.inverted

--- Returns a condition object equivalent to `self(...) or other(...)`
---@param other LuaSnip.SnipContext.Condition
---@return LuaSnip.SnipContext.ConditionObj
function ConditionObj:or_(other)
	return ConditionObj.make_condition(function(...)
		return self(...) or other(...)
	end)
end
--- (e.g. `cond1 + cond2`, implemented as `cond1:or_(cond2)`)
ConditionObj_mt.__add = ConditionObj.or_

--- Returns a condition object equivalent to `self(...) and not other(...)`
---
--- This is similar to set differences: `A \ B = {a in A | a not in B}`.
--- This makes `-(a + b) = -a - b` an identity representing de Morgan's law:
--- `not (a or b) = not a and not b`.
--- However, since boolean algebra lacks an additive inverse, `a + (-b) = a - b`
--- does not hold. Thus, this is NOT the same as `c1 + (-c2)`.
---
---@param other LuaSnip.SnipContext.Condition
---@return LuaSnip.SnipContext.ConditionObj
function ConditionObj:and_not(other)
	return ConditionObj.make_condition(function(...)
		return self(...) and not other(...)
	end)
end
--- (e.g. `cond1 - cond2`, implemented as `cond1:and_not(cond2)`)
ConditionObj_mt.__sub = ConditionObj.and_not

--- Returns a condition object equivalent to `self(...) and other(...)`
---@param other LuaSnip.SnipContext.Condition
---@return LuaSnip.SnipContext.ConditionObj
function ConditionObj:and_(other)
	return ConditionObj.make_condition(function(...)
		return self(...) and other(...)
	end)
end
--- (e.g. `cond1 * cond2`, implemented as `cond1:and_(cond2)`)
ConditionObj_mt.__mul = ConditionObj.and_

--- Returns a condition object equivalent to `self(...) ~= other(...)` (xor)
---@param other LuaSnip.SnipContext.Condition
---@return LuaSnip.SnipContext.ConditionObj
function ConditionObj:not_same_as(other)
	return ConditionObj.make_condition(function(...)
		return self(...) ~= other(...)
	end)
end
--- (e.g. `cond1 ^ cond2`, implemented as `cond1:not_same_as(cond2)`)
ConditionObj_mt.__pow = ConditionObj.not_same_as

--- Returns a condition object equivalent to `self(...) == other(...)` (xnor)
---@param other LuaSnip.SnipContext.Condition
---@return LuaSnip.SnipContext.ConditionObj
function ConditionObj:same_as(other)
	return ConditionObj.make_condition(function(...)
		return self(...) == other(...)
	end)
end
--- (e.g. `cond1 % cond2`, implemented as `cond1:same_as(cond2)`)
---
--- Using `%` might be counter intuitive, considering the `==`-operator exists,
--- unfortunately, it's not possible to use this for our purposes (some info
--- [here](https://github.com/L3MON4D3/LuaSnip/pull/612#issuecomment-1264487743)).
--- We decided instead to make use of a more obscure symbol (which will
--- hopefully avoid false assumptions about its meaning).
ConditionObj_mt.__mod = ConditionObj.same_as

return ConditionObj
