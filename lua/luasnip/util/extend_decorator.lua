local M = {}

-- map fn -> {arg_indx = int, extend = fn}[]
local function_properties = setmetatable({}, { __mode = "k" })

local function default_extend(arg, extend)
	return vim.tbl_extend("keep", arg or {}, extend or {})
end

---Create a new decorated version of `fn`.
---@param fn The function to create a decorator for.
---@vararg The values to extend with. These should match the descriptions passed
---in `register`:
---```lua
---local function somefn(arg1, arg2, opts1, opts2)
---...
---end
---register(somefn, {arg_indx=4}, {arg_indx=3})
---apply(somefn,
---	{key = "opts2 is extended with this"},
---	{key = "and opts1 with this"})
---```
---@return function: The decorated function.
function M.apply(fn, ...)
	local extend_properties = function_properties[fn]
	assert(
		extend_properties,
		"Cannot extend this function, it was not registered! Check :h luasnip-extend_decorator for more infos."
	)

	local extend_values = { ... }

	local decorated_fn = function(...)
		local direct_args = { ... }

		-- override values of direct argument.
		for i, ep in ipairs(extend_properties) do
			local arg_indx = ep.arg_indx

			-- still allow overriding with directly-passed keys.
			direct_args[arg_indx] =
				ep.extend(direct_args[arg_indx], extend_values[i])
		end

		-- important: http://www.lua.org/manual/5.3/manual.html#3.4
		-- Passing arguments after the results from `unpack` would mess all this
		-- up.
		return fn(unpack(direct_args))
	end

	-- we know how to extend the decorated function!
	function_properties[decorated_fn] = extend_properties

	return decorated_fn
end

---Prepare a function for usage with extend_decorator.
---To create a decorated function which extends `opts`-style tables passed to it, we need to know
--- 1. which parameter-position the opts are in and
--- 2. how to extend them.
---@param fn function: the function that should be registered.
---@vararg tables. Each describes how to extend one parameter to `fn`.
---The tables accept the following keys:
--- - arg_indx, number (required): the position of the parameter to override.
--- - extend, fn(arg, extend_value) -> effective_arg (optional): this function
---   is used to extend the args passed to the decorated function.
---   It defaults to a function which just extends the the arg-table with the
---   extend-table.
---   This extend-behaviour is adaptable to accomodate `s`, where the first
---   argument may be string or table.
function M.register(fn, ...)
	local fn_eps = { ... }

	-- make sure ep.extend is set.
	for _, ep in ipairs(fn_eps) do
		ep.extend = ep.extend or default_extend
	end

	function_properties[fn] = fn_eps
end

return M
