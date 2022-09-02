local builtin_namespace = require("luasnip.util._builtin_vars")

local function tbl_to_lazy_env(tbl)
	local function wrapper(varname)
		local val_ = tbl[varname]
		if type(val_) == "function" then
			return val_()
		end
		return val_
	end

	return wrapper
end

local namespaces = {}

-- Namespaces allow users to define their own environmet variables
local function _resolve_namespace_var(full_varname)
	local parts = vim.split(full_varname, "_")
	local nmsp = namespaces[parts[1]]

	local varname
	-- Is safe to fallback to the buitin-unnamed namespace as the checks in _env_namespace
	-- don't allow overriding those vars
	if nmsp then
		varname = full_varname:sub(#parts[1] + 2)
	else
		nmsp = namespaces[""]
		varname = full_varname
	end
	return nmsp, varname
end

local Environ = {}

function Environ.is_table(var_fullname)
	local nmsp, varname = _resolve_namespace_var(var_fullname)
	---@diagnostic disable-next-line: need-check-nil
	return nmsp.is_table(varname)
end

function Environ:new(info, o)
	o = o or {}
	setmetatable(o, self)
	vim.list_extend(info, info.pos) -- For compatibility with old user defined namespaces

	for ns_name, ns in pairs(namespaces) do
		local eager_vars = {}
		if ns.init then
			eager_vars = ns.init(info)
		end
		for _, eager in ipairs(ns.eager) do
			if not eager_vars[eager] then
				eager_vars[eager] = ns.vars(eager)
			end
		end

		local prefix = ""
		if ns_name ~= "" then
			prefix = ns_name .. "_"
		end

		for name, val in pairs(eager_vars) do
			name = prefix .. name
			rawset(o, name, val)
		end
	end
	return o
end

local builtin_ns_names = vim.inspect(vim.tbl_keys(builtin_namespace.builtin_ns))

local function _env_namespace(name, opts)
	assert(
		opts and type(opts) == "table",
		("Your opts for '%s' has to be a table"):format(name)
	)
	assert(
		opts.init or opts.vars,
		("Your opts for '%s' needs init or vars"):format(name)
	)

	-- namespace.eager → ns.vars
	assert(
		not opts.eager or opts.vars,
		("Your opts for %s can't set a `eager` field without the `vars` one"):format(
			name
		)
	)

	opts.eager = opts.eager or {}
	local multiline_vars = opts.multiline_vars or false

	local type_of_it = type(multiline_vars)

	assert(
		type_of_it == "table"
			or type_of_it == "boolean"
			or type_of_it == "function",
		("Your opts for %s can't have `multiline_vars` of type %s"):format(
			name,
			type_of_it
		)
	)

	-- If type is function we don't have to override it
	if type_of_it == "table" then
		local is_table_set = {}

		for _, key in ipairs(multiline_vars) do
			is_table_set[key] = true
		end

		opts.is_table = function(key)
			return is_table_set[key] or false
		end
	elseif type_of_it == "boolean" then
		opts.is_table = function(_)
			return multiline_vars
		end
	else -- is a function
		opts.is_table = multiline_vars
	end

	if opts.vars and type(opts.vars) == "table" then
		opts.vars = tbl_to_lazy_env(opts.vars)
	end

	namespaces[name] = opts
end

_env_namespace("", builtin_namespace)

-- The exposed api checks for the names to avoid accidental overrides
function Environ.env_namespace(name, opts)
	assert(
		name:match("^[a-zA-Z][a-zA-Z0-9]*$"),
		("You can't create a namespace with name '%s' it has to contain only and at least a non alpha-numeric character"):format(
			name
		)
	)
	assert(
		not builtin_namespace.builtin_ns[name],
		("You can't create a namespace with name '%s' because is one one of %s"):format(
			name,
			builtin_ns_names
		)
	)

	_env_namespace(name, opts)
end

function Environ:__index(key)
	local nmsp, varname = _resolve_namespace_var(key)
	---@diagnostic disable-next-line: need-check-nil
	local val = nmsp.vars(varname)

	rawset(self, key, val)

	return val
end

function Environ:override(env, new_env)
	for k, v in pairs(new_env) do
		env[k] = v
	end
end

local fake_env = {
	__index = function(tbl, key)
		local var
		if Environ.is_table(key) then
			var = { "$" .. key }
		else
			var = "$" .. key
		end
		rawset(tbl, key, var)
		return var
	end,
}

function Environ.fake()
	local o = {}
	setmetatable(o, fake_env)
	return o
end

return Environ
