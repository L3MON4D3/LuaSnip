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

return {
	lambda = lambda,

	--alias
	l = lambda,
}
