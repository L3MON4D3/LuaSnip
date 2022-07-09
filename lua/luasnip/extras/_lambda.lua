-- Mostly borrowed from https://github.com/lunarmodules/Penlight/ with just some changes to use
-- neovim internal functions and reformat
-- Copyright (C) 2009-2016 Steve Donovan, David Manura.

local concat, append = table.concat, table.insert
local map = vim.tbl_map

local _DEBUG = rawget(_G, "_DEBUG")

local function assert_arg(n, val, tp, verify, msg, lev)
	if type(val) ~= tp then
		error(
			("argument %d expected a '%s', got a '%s'"):format(n, tp, type(val)),
			lev or 2
		)
	end
	if verify and not verify(val) then
		error(("argument %d: '%s' %s"):format(n, val, msg), lev or 2)
	end
end

local lambda = {}

-- metatable for Placeholder Expressions (PE)
local _PEMT = {}

local function P(t)
	setmetatable(t, _PEMT)
	return t
end

lambda.PE = P

local function isPE(obj)
	return getmetatable(obj) == _PEMT
end

lambda.isPE = isPE

-- construct a placeholder variable (e.g _1 and _2)
local function PH(idx)
	return P({ op = "X", repr = "args[" .. idx .. "]", index = idx })
end

-- construct a constant placeholder variable (e.g _C1 and _C2)
local function CPH(idx)
	return P({ op = "X", repr = "_C" .. idx, index = idx })
end

lambda._1, lambda._2, lambda._3, lambda._4, lambda._5 =
	PH(1), PH(2), PH(3), PH(4), PH(5)
lambda._0 = P({ op = "X", repr = "...", index = 0 })

function lambda.Var(name)
	local ls = vim.split(name, "[%s,]+")
	local res = {}
	for i = 1, #ls do
		append(res, P({ op = "X", repr = ls[i], index = 0 }))
	end
	return unpack(res)
end

function lambda._(value)
	return P({ op = "X", repr = value, index = "wrap" })
end

-- unknown keys are some named variable.
setmetatable(lambda, {
	__index = function(_, key)
		-- \\n to be correctly interpreted in `load()`.
		return P({
			op = "X",
			repr = "args." .. key,
			index = 0,
		})
	end,
})

local repr

lambda.Nil = lambda.Var("nil")

function _PEMT.__index(obj, key)
	return P({ op = "[]", obj, key })
end

function _PEMT.__call(fun, ...)
	return P({ op = "()", fun, ... })
end

function _PEMT.__tostring(e)
	return repr(e)
end

function _PEMT.__unm(arg)
	return P({ op = "unm", arg })
end

function lambda.Not(arg)
	return P({ op = "not", arg })
end

function lambda.Len(arg)
	return P({ op = "#", arg })
end

local function binreg(context, t)
	for name, op in pairs(t) do
		rawset(context, name, function(x, y)
			return P({ op = op, x, y })
		end)
	end
end

local function import_name(name, fun, context)
	rawset(context, name, function(...)
		return P({ op = "()", fun, ... })
	end)
end

local imported_functions = {}

local function is_global_table(n)
	return type(_G[n]) == "table"
end

--- wrap a table of functions. This makes them available for use in
-- placeholder expressions.
-- @string tname a table name
-- @tab context context to put results, defaults to environment of caller
function lambda.import(tname, context)
	assert_arg(
		1,
		tname,
		"string",
		is_global_table,
		"arg# 1: not a name of a global table"
	)
	local t = _G[tname]
	context = context or _G
	for name, fun in pairs(t) do
		import_name(name, fun, context)
		imported_functions[fun] = name
	end
end

--- register a function for use in placeholder expressions.
-- @lambda fun a function
-- @string[opt] name an optional name
-- @return a placeholder functiond
function lambda.register(fun, name)
	assert_arg(1, fun, "function")
	if name then
		assert_arg(2, name, "string")
		imported_functions[fun] = name
	end
	return function(...)
		return P({ op = "()", fun, ... })
	end
end

function lambda.lookup_imported_name(fun)
	return imported_functions[fun]
end

local function _arg(...)
	return ...
end

function lambda.Args(...)
	return P({ op = "()", _arg, ... })
end

-- binary operators with their precedences (see Lua manual)
-- precedences might be incremented by one before use depending on
-- left- or right-associativity, space them out
local binary_operators = {
	["or"] = 0,
	["and"] = 2,
	["=="] = 4,
	["~="] = 4,
	["<"] = 4,
	[">"] = 4,
	["<="] = 4,
	[">="] = 4,
	[".."] = 6,
	["+"] = 8,
	["-"] = 8,
	["*"] = 10,
	["/"] = 10,
	["%"] = 10,
	["^"] = 14,
}

-- unary operators with their precedences
local unary_operators = {
	["not"] = 12,
	["#"] = 12,
	["unm"] = 12,
}

-- comparisons (as prefix functions)
binreg(lambda, {
	And = "and",
	Or = "or",
	Eq = "==",
	Lt = "<",
	Gt = ">",
	Le = "<=",
	Ge = ">=",
})

-- standard binary operators (as metamethods)
binreg(_PEMT, {
	__add = "+",
	__sub = "-",
	__mul = "*",
	__div = "/",
	__mod = "%",
	__pow = "^",
	__concat = "..",
})

binreg(_PEMT, { __eq = "==" })

--- all elements of a table except the first.
-- @tab ls a list-like table.
function lambda.tail(ls)
	assert_arg(1, ls, "table")
	local res = {}
	for i = 2, #ls do
		append(res, ls[i])
	end
	return res
end

--- create a string representation of a placeholder expression.
-- @param e a placeholder expression
-- @param lastpred not used
function repr(e, lastpred)
	local tail = lambda.tail
	if isPE(e) then
		local pred = binary_operators[e.op] or unary_operators[e.op]
		if pred then
			-- binary or unary operator
			local s
			if binary_operators[e.op] then
				local left_pred = pred
				local right_pred = pred
				if e.op == ".." or e.op == "^" then
					left_pred = left_pred + 1
				else
					right_pred = right_pred + 1
				end
				local left_arg = repr(e[1], left_pred)
				local right_arg = repr(e[2], right_pred)
				s = left_arg .. " " .. e.op .. " " .. right_arg
			else
				local op = e.op == "unm" and "-" or e.op
				s = op .. " " .. repr(e[1], pred)
			end
			if lastpred and lastpred > pred then
				s = "(" .. s .. ")"
			end
			return s
		else -- either postfix, or a placeholder
			local ls = map(repr, e)
			if e.op == "[]" then
				return ls[1] .. "[" .. ls[2] .. "]"
			elseif e.op == "()" then
				local fn
				if ls[1] ~= nil then -- was _args, undeclared!
					fn = ls[1]
				else
					fn = ""
				end
				return fn .. "(" .. concat(tail(ls), ",") .. ")"
			else
				return e.repr
			end
		end
	elseif type(e) == "string" then
		return '"' .. e .. '"'
	elseif type(e) == "function" then
		local name = lambda.lookup_imported_name(e)
		if name then
			return name
		else
			return tostring(e)
		end
	else
		return tostring(e) --should not really get here!
	end
end
lambda.repr = repr

-- collect all the non-PE values in this PE into vlist, and replace each occurence
-- with a constant PH (_C1, etc). Return the maximum placeholder index found.
local collect_values
function collect_values(e, vlist)
	if isPE(e) then
		if e.op ~= "X" then
			local m = 0
			for i = 1, #e do
				local subx = e[i]
				local pe = isPE(subx)
				if pe then
					if subx.op == "X" and subx.index == "wrap" then
						subx = subx.repr
						pe = false
					else
						m = math.max(m, collect_values(subx, vlist))
					end
				end
				if not pe then
					append(vlist, subx)
					e[i] = CPH(#vlist)
				end
			end
			return m
		else -- was a placeholder, it has an index...
			return e.index
		end
	else -- plain value has no placeholder dependence
		return 0
	end
end
lambda.collect_values = collect_values

--- instantiate a PE into an actual function. First we find the largest placeholder used,
-- e.g. _2; from this a list of the formal parameters can be build. Then we collect and replace
-- any non-PE values from the PE, and build up a constant binding list.
-- Finally, the expression can be compiled, and e.__PE_function is set.
-- @param e a placeholder expression
-- @return a function
function lambda.instantiate(e)
	local consts, values = {}, {}
	local rep, err, fun
	local n = lambda.collect_values(e, values)
	for i = 1, #values do
		append(consts, "_C" .. i)
		if _DEBUG then
			print(i, values[i])
		end
	end

	consts = concat(consts, ",")
	rep = repr(e)
	local fstr = ("return function(%s) return function(args) return %s end end"):format(
		consts,
		rep
	)
	if _DEBUG then
		print(fstr)
	end
	fun, err = load(fstr, "fun")
	if not fun then
		return nil, err
	end
	fun = fun() -- get wrapper
	fun = fun(unpack(values)) -- call wrapper (values could be empty)
	e.__PE_function = fun
	return fun
end

--- instantiate a PE unless it has already been done.
-- @param e a placeholder expression
-- @return the function
function lambda.I(e)
	if rawget(e, "__PE_function") then
		return e.__PE_function
	else
		return lambda.instantiate(e)
	end
end

return lambda
