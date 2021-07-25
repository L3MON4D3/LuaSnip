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
	assert(_match, "You have to pass at least 2 arguments")
	assert(type(index) == "number", "Index has to be a single number")

	_match = to_function(_match, true)
	_then = to_function(_then or function(text)
		local match_return = _match(text)
		return (type(match_return) == "string" and match_return) or ""
	end)
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
	-- repeat a node.
	rep = function(node_indx)
		return F(function(args)
			return args[1]
		end, node_indx)
	end,
	-- Insert the output of a function.
	partial = function(func, ...)
		return F(function(_, fn, ...)
			return fn(...)
		end, {}, func, ...)
	end,
	nonempty = function(indx, text_if, text_if_not)
		assert(type(indx) == "number", "this only checks one node for emptiness!")
		assert(text_if, "At least the text for nonemptiness has to be supplied.")

		return F(function(args)
			return (args[1][1] ~= "" or #args[1]>1) and text_if or (text_if_not or "")
		end, {indx})
	end,

	--alias
	l = lambda,
	m = match,
}
