local ls = require'luasnip'
local uv = vim.loop


local function json_decode(data)
  local status, result = pcall(vim.fn.json_decode, data)
  if status then
    return result
  else
    return nil, result
  end
end

local sep = (function()
  if jit then
    local os = string.lower(jit.os)
    if os == 'linux' or os == 'osx' or os == 'bsd' then
      return '/'
    else
      return '\\'
    end
  else
    return package.config:sub(1, 1)
  end
end)()

local function path_join(a, b)
    return table.concat({a, b}, sep)
end
local function path_exists(path)
    return uv.fs_stat(path) and true or false
end

local function file_read(path)
    local fd = uv.fs_open(path, "r", 438)
    local stat = uv.fs_fstat(fd)
    local data = uv.fs_read(fd, stat.size, 0)
    uv.fs_close(fd)

    return data
end


local function load_snippet_file(langs, snippet_set_path)
    if not path_exists(snippet_set_path) then return end
    local snippet_set_data = json_decode(file_read(snippet_set_path))

    for _, lang in pairs(langs) do
        local lang_snips = ls.snippets[lang] or {}

        for name, parts in pairs(snippet_set_data) do
            local body = type(parts.body) == "string" and parts.body or table.concat(parts.body, '\n')

            -- There are still some snippets that fail while loading
            pcall(function()
                -- Sometimes it's a list of prefixes instead of a single one
                local prefixes = type(parts.prefix) == "table" and parts.prefix or {parts.prefix}
                for _, prefix in ipairs(prefixes) do
                    table.insert(
                        lang_snips,
                        ls.parser.parse_snippet({trig=prefix, name=name, wordTrig=true}, body)
                    )
                end
            end)
        end
        ls.snippets[lang] = lang_snips
    end
end

local function load_snippet_folder(root)
    local package = path_join(root, 'package.json')
    if not path_exists(package) then return end
    local package_data = json_decode(file_read(package))
    if not (package_data and package_data.contributes and package_data.contributes.snippets)  then return end

    for _, snippet_entry in pairs(package_data.contributes.snippets) do
        local langs = snippet_entry.language

        if (type(snippet_entry.language) ~= "table") then
            langs = {langs}
        end

        load_snippet_file(langs, path_join(root, snippet_entry.path))
    end
end

local M = {}

function M.load()
    for path in vim.o.runtimepath:gmatch('([^,]+)') do
        load_snippet_folder(path)
    end
end

return M
