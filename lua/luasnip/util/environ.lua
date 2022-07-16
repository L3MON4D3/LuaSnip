local builtin_vars = require("luasnip.util._builtin_vars")



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

local namespaces = {
    [""] = {
        init = builtin_vars.eager,
        vars = tbl_to_lazy_env(builtin_vars.lazy),
        eager = {},
        is_table = builtin_vars.is_table
    }
}

-- Namespaces allow users to define their own environmet variables
local function _resolve_namespace_var(full_varname)
    local parts = vim.split(full_varname, '_')
    if #parts < 2 then return nil end
    local nmsp = namespaces[parts[1]]

    local varname

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

function Environ:new(pos, o)
    o = o or {}
    setmetatable(o, self)

    for ns_name, ns in pairs(namespaces) do
        local eager_vars = {}
        if ns.init then
            eager_vars = ns.init(pos)
        end
        for _, eager in ipairs(ns.eager) do
           if not eager_vars[eager] then
               eager_vars[eager]  = ns.vars(eager)
           end
        end

        local prefix = ""
        if ns_name ~= "" then
            prefix = ns_name .. "_"
        end

        for name, val in pairs(eager_vars) do
            name = prefix .. name
            local val_type = type(val)
            if val and val_type ~= "string" and val_type ~= "table" then
                val = tostring(val)
            end
            rawset(o, name, val)
        end
    end
    return o
end

local builtin_ns_names = vim.inspect(vim.tbl_keys(builtin_vars.builtin_ns))

function Environ.env_namespace(name, namespace)
    assert(#name > 0 and not (name:find("_")), ("You can't create a namespace with name '%s' empty nor containing _"):format(name))
    assert(not builtin_vars.builtin_ns[name], ("You can't create a namespace with name '%s' because is one one of %s"):format(name, builtin_ns_names))
    local ns = namespace

    assert(ns and type(ns) == 'table', ("Your namespace '%s' has to be a table"):format(name))
    assert(ns.init or ns.vars,( "Your namespace '%s' needs init or vars"):format(name))

    -- namespace.eager → ns.vars
    assert(not ns.eager or ns.vars, ("Your namespace %s can't set a `eager` field without the `vars` one"):format(name))

    ns.eager = ns.eager or {}
    local is_table = ns.is_table or false

    local type_of_it = type(multiline_vars)

    assert(type_of_it == "table" or type_of_it == "boolean" or type_of_it == "function", ("Your namespace %s can't have `is_table` of type %s"):format(name, type_of_it))

    -- If type is function we don't have to override it
    if type_of_it == "table" then
        local is_table_set = {}

        for _, key in ipairs(multiline_vars) do
            is_table_set[key] = true
        end

        ns.is_table = function (key)
            return is_table_set[key] or false
        end

    elseif type_of_it == "boolean" then
        opts.is_table = function(_) return multiline_vars end
    else -- is a function
        opts.is_table = multiline_vars
    end


    if ns.vars and type(ns.vars) == "table" then
        ns.vars = tbl_to_lazy_env(ns.vars)
    end


    namespaces[name] = ns
end

function Environ:__index(key)

    local nmsp, varname = _resolve_namespace_var(key)
---@diagnostic disable-next-line: need-check-nil
    local val = nmsp.vars(varname) or ""

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
         var = {"$" .. key}
     else
         var = "$" .. key
     end
        rawset(tbl, key, var)
        return var
    end
}

function Environ.fake()
    local o = {}
    setmetatable(o, fake_env)
    return o
end

return Environ
