local F = require("luasnip.nodes.functionNode").F

local lambda = {}

local function _concat(lines)
	return table.concat(lines, "\n")
end

local function expr_to_fn(expr)
	local _lambda = require("luasnip.extras._lambda")

	local fn_code = _lambda.instantiate(expr)
	local function fn(args)
		local inputs = vim.tbl_map(_concat, args)
		local out = fn_code(unpack(inputs))
		return vim.split(out, "\n")
	end
	return fn
end

local LM = {}
function LM:__index(key)
	return require("luasnip.extras._lambda")[key]
end
function LM:__call(expr, input_ids)
	return F(expr_to_fn(expr), input_ids)
end

setmetatable(lambda, LM)

local function to_function(val, use_re)
	if type(val) == "function" then
		return val
	end
	if type(val) == "string" and not use_re then
		return function()
			return val
		end
	end
	if type(val) == "string" and use_re then
		return function(arg)
			return arg:match(val)
		end
	end
	if lambda.isPE(val) then
		return lambda.instantiate(val)
	end
	assert(false, "Can't convert argument to function")
end

local function match(index, _match, _then, _else)
	assert(_then, "You have to pass at least 2 arguments")
	assert(type(index) == "number", "Index has to be a single number")

	_then = to_function(_then)
	_match = to_function(_match or "^$", true)
	_else = to_function(_else or "")

	local function func(arg)
		local text = _concat(arg[1])
		local out = nil
		if _match(text) then
			out = _then(text)
		else
			out = _else(text)
		end
		return vim.split(out, "\n")
	end

	return F(func, { index })
end

return {
	lambda = lambda,
	match = match,
	--alias
	l = lambda,
	m = match,
}
