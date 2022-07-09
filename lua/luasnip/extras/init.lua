local F = require("luasnip.nodes.functionNode").F
local SN = require("luasnip.nodes.snippet").SN
local D = require("luasnip.nodes.dynamicNode").D
local I = require("luasnip.nodes.insertNode").I

local lambda = {}

local function _concat(lines)
	return table.concat(lines, "\n")
end

local function make_lambda_args(node_args, imm_parent)
	local snip = imm_parent.snippet
	-- turn args' table-multilines into \n-multilines (needs to be possible
	-- to process args with luas' string-functions).
	local args = vim.tbl_map(_concat, node_args)

	setmetatable(args, {
		__index = function(table, key)
			local val
			-- key may be capture or env-variable.
			local num = key:match("CAPTURE(%d+)")
			if num then
				val = snip.captures[tonumber(num)]
			else
				-- env may be string or table.
				if type(snip.env[key]) == "table" then
					-- table- to \n-multiline.
					val = _concat(snip.env[key])
				else
					val = snip.env[key]
				end
			end
			rawset(table, key, val)
			return val
		end,
	})
	return args
end

local function expr_to_fn(expr)
	local _lambda = require("luasnip.extras._lambda")

	local fn_code = _lambda.instantiate(expr)
	local function fn(args, snip)
		-- to be sure, lambda may end with a `match` returning nil.
		local out = fn_code(make_lambda_args(args, snip)) or ""
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
		return function(args)
			return _concat(args[1]):match(val)
		end
	end
	if lambda.isPE(val) then
		local lmb = lambda.instantiate(val)
		return function(args, snip)
			return lmb(make_lambda_args(args, snip))
		end
	end
	assert(false, "Can't convert argument to function")
end

local function match(index, _match, _then, _else)
	assert(_match, "You have to pass at least 2 arguments")

	_match = to_function(_match, true)
	_then = to_function(_then or function(args, snip)
		local match_return = _match(args, snip)
		return (
			(
				type(match_return) == "string"
				-- _assume_ table of string.
				or type(match_return) == "table"
			) and match_return
		) or ""
	end)
	_else = to_function(_else or "")

	local function func(args, snip)
		local out = nil
		if _match(args, snip) then
			out = _then(args, snip)
		else
			out = _else(args, snip)
		end
		-- \n is used as a line-separator for simple strings.
		return type(out) == "string" and vim.split(out, "\n") or out
	end

	return F(func, index)
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
		return F(function(_, _, ...)
			return func(...)
		end, {}, { user_args = { ... } })
	end,
	nonempty = function(indx, text_if, text_if_not)
		assert(
			type(indx) == "number",
			"this only checks one node for emptiness!"
		)
		assert(
			text_if,
			"At least the text for nonemptiness has to be supplied."
		)

		return F(function(args)
			return (args[1][1] ~= "" or #args[1] > 1) and text_if
				or (text_if_not or "")
		end, {
			indx,
		})
	end,
	dynamic_lambda = function(pos, lambd, args_indcs)
		local insert_preset_text_func = lambda.instantiate(lambd)
		return D(pos, function(args, imm_parent)
			-- to be sure, lambda may end with a `match` returning nil.
			local out = insert_preset_text_func(
				make_lambda_args(args, imm_parent)
			) or ""
			return SN(pos, {
				I(1, vim.split(out, "\n")),
			})
		end, args_indcs)
	end,

	--alias
	l = lambda,
	m = match,
}
